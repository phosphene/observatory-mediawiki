// Package test runs the Observatory compliance BDD suite.
//
// Follows phosphene/go_bdd_reference methodology:
//   - Gherkin feature files are the contract (../features/)
//   - Step definitions are the proof (this file)
//   - testcontainers-go/modules/compose boots the hermetic stack
//   - baseline.json is the data invariant oracle
//   - Direct DB connection proves state at the data layer
//
// Usage:
//
//	make test                                         # full suite
//	go test -v ./test/... -timeout 15m               # verbose
//	MW_BASE_URL=http://x:80 go test -v ./test/...    # skip boot
package test

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/cucumber/godog"
	mwclient "github.com/phosphene/observatory-mediawiki/tests/compliance/internal/mediawiki"
	dbclient "github.com/phosphene/observatory-mediawiki/tests/compliance/internal/db"
	"github.com/testcontainers/testcontainers-go/modules/compose"
	"github.com/testcontainers/testcontainers-go/wait"
)

// ---------------------------------------------------------------------------
// Suite-level state — set in TestMain, shared across all scenarios
// ---------------------------------------------------------------------------

var (
	mw       *mwclient.Client
	dbConn   *dbclient.Client
	baseline V1Baseline
)

// ---------------------------------------------------------------------------
// V1Baseline — the ground truth data invariant
// ---------------------------------------------------------------------------

type V1Baseline struct {
	Sitename       string            `json:"sitename"`
	DBType         string            `json:"dbtype"`
	DBVersion      string            `json:"dbversion"`
	DefaultSkin    string            `json:"default_skin"`
	Extensions     []string          `json:"extensions"`
	ExtensionCount int               `json:"extension_count"`
	Namespaces     map[string]string `json:"namespaces"`
	NamespaceCount int               `json:"namespace_count"`
}

// KnownDivergences — intentional V1→V2 differences.
// Not failures. Any unlisted divergence fails the test.
var KnownDivergences = map[string]string{
	"redis:removed": "CACHE_NONE confirmed from V1 env; removed deliberately",
}

// ---------------------------------------------------------------------------
// TestMain — boots the compose stack once for all scenarios
// ---------------------------------------------------------------------------

func TestMain(m *testing.M) {
	loadBaselineOrExit()

	if url := os.Getenv("MW_BASE_URL"); url != "" {
		// Skip boot — use an already-running container
		mw = mwclient.NewClient(url, nil)
		fmt.Printf("Using existing container at %s\n", url)
		os.Exit(m.Run())
	}

	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Minute)
	defer cancel()

	_, thisFile, _, _ := runtime.Caller(0)
	composePath := filepath.Join(filepath.Dir(thisFile), "testdata", "docker-compose.yml")

	stack, err := compose.NewDockerCompose(composePath)
	if err != nil {
		fmt.Printf("could not create compose stack: %v\n", err)
		os.Exit(1)
	}

	// Wait strategies: MW API must return 200 before tests run
	stack.WaitForService("web",
		wait.ForHTTP("/w/api.php?action=query&meta=siteinfo&format=json").
			WithPort("80/tcp").
			WithStartupTimeout(10*time.Minute).
			WithPollInterval(5*time.Second),
	)

	if err := stack.Up(ctx, compose.Wait(true)); err != nil {
		fmt.Printf("could not start compose stack: %v\n", err)
		os.Exit(1)
	}
	defer func() {
		_ = stack.Down(context.Background(), compose.RemoveOrphans(true))
	}()

	// Discover MW container dynamic port
	webContainer, err := stack.ServiceContainer(ctx, "web")
	if err != nil {
		fmt.Printf("could not get web container: %v\n", err)
		os.Exit(1)
	}
	webHost, err := webContainer.Host(ctx)
	if err != nil {
		fmt.Printf("could not get web host: %v\n", err)
		os.Exit(1)
	}
	webPort, err := webContainer.MappedPort(ctx, "80/tcp")
	if err != nil {
		fmt.Printf("could not get web port: %v\n", err)
		os.Exit(1)
	}
	baseURL := fmt.Sprintf("http://%s:%s", webHost, webPort.Port())
	mw = mwclient.NewClient(baseURL, nil)
	fmt.Printf("Observatory web running at %s\n", baseURL)

	// Discover DB container dynamic port — direct connection for data invariants
	dbContainer, err := stack.ServiceContainer(ctx, "db")
	if err != nil {
		fmt.Printf("could not get db container: %v\n", err)
		os.Exit(1)
	}
	dbHost, err := dbContainer.Host(ctx)
	if err != nil {
		fmt.Printf("could not get db host: %v\n", err)
		os.Exit(1)
	}
	dbPort, err := dbContainer.MappedPort(ctx, "3306/tcp")
	if err != nil {
		fmt.Printf("could not get db port: %v\n", err)
		os.Exit(1)
	}
	dbConn, err = dbclient.NewClient(dbHost, dbPort.Port(),
		"root", "compliance_root_pass", "observatory_compliance")
	if err != nil {
		fmt.Printf("could not connect to DB: %v\n", err)
		os.Exit(1)
	}
	defer dbConn.Close()
	fmt.Printf("Observatory DB at %s:%s\n", dbHost, dbPort.Port())

	os.Exit(m.Run())
}

// ---------------------------------------------------------------------------
// TestFeatures — godog BDD runner
// ---------------------------------------------------------------------------

func TestFeatures(t *testing.T) {
	suite := godog.TestSuite{
		ScenarioInitializer: initializeScenario,
		Options: &godog.Options{
			Format:   "pretty",
			Paths:    []string{"../features"},
			TestingT: t,
		},
	}
	if suite.Run() != 0 {
		t.Fatal("compliance suite: one or more scenarios failed")
	}
}

// ---------------------------------------------------------------------------
// Scenario state — fresh per scenario
// ---------------------------------------------------------------------------

type state struct {
	responseStatus int
	responseBody   string
	apiData        map[string]any
}

// ---------------------------------------------------------------------------
// Step registration
// ---------------------------------------------------------------------------

func initializeScenario(sc *godog.ScenarioContext) {
	s := &state{}

	// Context
	sc.Step(`^the Observatory stack is running$`, s.theObservatoryStackIsRunning)
	sc.Step(`^the V1 baseline is loaded$`, s.theV1BaselineIsLoaded)
	sc.Step(`^the database connection is established$`, s.theDatabaseConnectionIsEstablished)

	// Actions — HTTP
	sc.Step(`^I request the MediaWiki API siteinfo$`, s.iRequestSiteinfo)
	sc.Step(`^I request the loaded extensions$`, s.iRequestExtensions)
	sc.Step(`^I request the site namespaces$`, s.iRequestNamespaces)
	sc.Step(`^I request the loaded skins$`, s.iRequestSkins)
	sc.Step(`^I request "([^"]*)"$`, s.iRequest)

	// Assertions — API
	sc.Step(`^the API response should be valid JSON$`, s.theAPIResponseIsValidJSON)
	sc.Step(`^the API response should contain a "([^"]*)" key$`, s.theAPIResponseContainsKey)
	sc.Step(`^the sitename should be "([^"]*)"$`, s.theSitenameShouldBe)
	sc.Step(`^the database type should be "([^"]*)"$`, s.theDBTypeShouldBe)
	sc.Step(`^the database version should be "([^"]*)"$`, s.theDBVersionShouldBe)
	sc.Step(`^all V1 baseline extensions should be present$`, s.allV1ExtensionsShouldBePresent)
	sc.Step(`^the extension count should be at least (\d+)$`, s.theExtensionCountShouldBeAtLeast)
	sc.Step(`^all V1 baseline namespaces should be present with correct names$`, s.allV1NamespacesShouldBePresent)
	sc.Step(`^the default skin should be "([^"]*)" or a known divergence$`, s.theDefaultSkinOrKnownDivergence)

	// Assertions — HTTP
	sc.Step(`^the response status should be (\d+)$`, s.theResponseStatusShouldBe)
	sc.Step(`^the response body should contain "([^"]*)"$`, s.theResponseBodyShouldContain)
	sc.Step(`^the response body should not contain "([^"]*)"$`, s.theResponseBodyShouldNotContain)

	// Assertions — DB (data invariants)
	sc.Step(`^the "([^"]*)" table should exist in the database$`, s.theTableShouldExist)
	sc.Step(`^the page count should be at least (\d+)$`, s.thePageCountShouldBeAtLeast)
}

// ---------------------------------------------------------------------------
// Context steps
// ---------------------------------------------------------------------------

func (s *state) theObservatoryStackIsRunning() error {
	if mw == nil {
		return fmt.Errorf("Observatory stack not running — mw client is nil")
	}
	return nil
}

func (s *state) theV1BaselineIsLoaded() error {
	if len(baseline.Extensions) == 0 {
		return fmt.Errorf("V1 baseline not loaded — run capture-baseline.sh against V1")
	}
	return nil
}

func (s *state) theDatabaseConnectionIsEstablished() error {
	if dbConn == nil {
		return fmt.Errorf("DB connection not established")
	}
	return nil
}

// ---------------------------------------------------------------------------
// Action steps
// ---------------------------------------------------------------------------

func (s *state) iRequestSiteinfo() error {
	return s.apiGet("action=query&meta=siteinfo&siprop=general")
}

func (s *state) iRequestExtensions() error {
	return s.apiGet("action=query&meta=siteinfo&siprop=extensions")
}

func (s *state) iRequestNamespaces() error {
	return s.apiGet("action=query&meta=siteinfo&siprop=namespaces")
}

func (s *state) iRequestSkins() error {
	return s.apiGet("action=query&meta=siteinfo&siprop=skins")
}

func (s *state) iRequest(path string) error {
	status, body, err := mw.Get(path)
	if err != nil {
		return err
	}
	s.responseStatus = status
	s.responseBody = body
	return nil
}

func (s *state) apiGet(params string) error {
	if err := mw.API(params, &s.apiData); err != nil {
		return err
	}
	return nil
}

// ---------------------------------------------------------------------------
// API assertion steps
// ---------------------------------------------------------------------------

func (s *state) theAPIResponseIsValidJSON() error {
	if s.apiData == nil {
		return fmt.Errorf("API response is not valid JSON")
	}
	return nil
}

func (s *state) theAPIResponseContainsKey(key string) error {
	if _, ok := s.apiData[key]; !ok {
		return fmt.Errorf("API response missing key %q", key)
	}
	return nil
}

func (s *state) theSitenameShouldBe(expected string) error {
	actual, _ := s.general()["sitename"].(string)
	if actual != expected {
		return fmt.Errorf("sitename: expected %q, got %q", expected, actual)
	}
	return nil
}

func (s *state) theDBTypeShouldBe(expected string) error {
	actual, _ := s.general()["dbtype"].(string)
	if actual != expected {
		return fmt.Errorf("dbtype: expected %q, got %q", expected, actual)
	}
	return nil
}

func (s *state) theDBVersionShouldBe(expected string) error {
	actual, _ := s.general()["dbversion"].(string)
	if actual != expected {
		return fmt.Errorf("dbversion: expected %q, got %q", expected, actual)
	}
	return nil
}

func (s *state) allV1ExtensionsShouldBePresent() error {
	query, _ := s.apiData["query"].(map[string]any)
	exts, _ := query["extensions"].([]any)

	v2set := make(map[string]bool, len(exts))
	for _, e := range exts {
		if m, ok := e.(map[string]any); ok {
			if name, ok := m["name"].(string); ok {
				v2set[name] = true
			}
		}
	}

	var missing []string
	for _, name := range baseline.Extensions {
		if !v2set[name] {
			missing = append(missing, name)
		}
	}
	sort.Strings(missing)

	if len(missing) > 0 {
		return fmt.Errorf("missing %d V1 extensions: %v", len(missing), missing)
	}
	return nil
}

func (s *state) theExtensionCountShouldBeAtLeast(min int) error {
	query, _ := s.apiData["query"].(map[string]any)
	exts, _ := query["extensions"].([]any)
	if len(exts) < min {
		return fmt.Errorf("extension count %d < minimum %d", len(exts), min)
	}
	return nil
}

func (s *state) allV1NamespacesShouldBePresent() error {
	query, _ := s.apiData["query"].(map[string]any)
	nsMap, _ := query["namespaces"].(map[string]any)

	v2ns := make(map[string]string)
	for k, v := range nsMap {
		if m, ok := v.(map[string]any); ok {
			name, _ := m["*"].(string)
			if name == "" {
				name, _ = m["canonical"].(string)
			}
			v2ns[k] = name
		}
	}

	var failures []string
	for nsID, nsName := range baseline.Namespaces {
		v2Name, exists := v2ns[nsID]
		if !exists {
			failures = append(failures, fmt.Sprintf("NS %s (%s) missing", nsID, nsName))
		} else if v2Name != nsName {
			failures = append(failures, fmt.Sprintf("NS %s: expected %q got %q", nsID, nsName, v2Name))
		}
	}
	sort.Strings(failures)

	if len(failures) > 0 {
		return fmt.Errorf("%d namespace failures:\n%s", len(failures), strings.Join(failures, "\n"))
	}
	return nil
}

func (s *state) theDefaultSkinOrKnownDivergence(expected string) error {
	query, _ := s.apiData["query"].(map[string]any)
	skins, _ := query["skins"].([]any)

	var defaultSkin string
	for _, sk := range skins {
		if m, ok := sk.(map[string]any); ok {
			if _, hasDefault := m["default"]; hasDefault {
				defaultSkin, _ = m["code"].(string)
			}
		}
	}

	if defaultSkin == expected {
		return nil
	}

	key := fmt.Sprintf("default_skin:%s→%s", expected, defaultSkin)
	if reason, ok := KnownDivergences[key]; ok {
		fmt.Printf("  KNOWN DIVERGENCE: %s — %s\n", key, reason)
		return nil
	}

	return fmt.Errorf("default_skin=%q (expected %q) — not in KnownDivergences; add it or fix it",
		defaultSkin, expected)
}

// ---------------------------------------------------------------------------
// HTTP assertion steps
// ---------------------------------------------------------------------------

func (s *state) theResponseStatusShouldBe(expected int) error {
	if s.responseStatus != expected {
		return fmt.Errorf("status: expected %d, got %d", expected, s.responseStatus)
	}
	return nil
}

func (s *state) theResponseBodyShouldContain(expected string) error {
	if !strings.Contains(s.responseBody, expected) {
		return fmt.Errorf("body does not contain %q", expected)
	}
	return nil
}

func (s *state) theResponseBodyShouldNotContain(unexpected string) error {
	if strings.Contains(s.responseBody, unexpected) {
		return fmt.Errorf("body should not contain %q", unexpected)
	}
	return nil
}

// ---------------------------------------------------------------------------
// DB data invariant steps
// ---------------------------------------------------------------------------

func (s *state) theTableShouldExist(table string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	exists, err := dbConn.TableExists(ctx, table)
	if err != nil {
		return fmt.Errorf("theTableShouldExist(%s): %w", table, err)
	}
	if !exists {
		return fmt.Errorf("table %q does not exist in the database", table)
	}
	return nil
}

func (s *state) thePageCountShouldBeAtLeast(min int) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	count, err := dbConn.PageCount(ctx)
	if err != nil {
		return fmt.Errorf("thePageCountShouldBeAtLeast: %w", err)
	}
	if count < min {
		return fmt.Errorf("page count %d < minimum %d", count, min)
	}
	return nil
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func (s *state) general() map[string]any {
	query, _ := s.apiData["query"].(map[string]any)
	general, _ := query["general"].(map[string]any)
	return general
}

func loadBaselineOrExit() {
	_, thisFile, _, _ := runtime.Caller(0)
	path := filepath.Join(filepath.Dir(thisFile), "testdata", "baseline.json")
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Printf("could not load baseline.json: %v\n", err)
		os.Exit(1)
	}
	if err := json.Unmarshal(data, &baseline); err != nil {
		fmt.Printf("could not parse baseline.json: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Baseline loaded: %d extensions, %d namespaces\n",
		baseline.ExtensionCount, baseline.NamespaceCount)
}
