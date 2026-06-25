// Package mediawiki provides a thin client for the MediaWiki Action API.
// It is the only package that knows about HTTP — domain types are clean.
package mediawiki

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// Client is a MediaWiki Action API client.
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient returns a Client pointed at baseURL (e.g. "http://10.x.x.x:80").
func NewClient(baseURL string, httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &Client{baseURL: baseURL, httpClient: httpClient}
}

// Get fetches a raw URL and returns status code + body.
func (c *Client) Get(path string) (int, string, error) {
	resp, err := c.httpClient.Get(c.baseURL + path)
	if err != nil {
		return 0, "", fmt.Errorf("GET %s: %w", path, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return resp.StatusCode, "", err
	}
	return resp.StatusCode, string(body), nil
}

// API calls the MediaWiki Action API with the given query params and
// unmarshals the JSON response into out.
func (c *Client) API(params string, out any) error {
	url := fmt.Sprintf("%s/w/api.php?%s&format=json", c.baseURL, params)
	resp, err := c.httpClient.Get(url)
	if err != nil {
		return fmt.Errorf("api %s: %w", params, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("api %s: unmarshal: %w (body: %s)", params, err, body[:min(len(body), 200)])
	}
	return nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// SiteinfoGeneral holds the fields we care about from action=query&meta=siteinfo&siprop=general.
type SiteinfoGeneral struct {
	Sitename  string `json:"sitename"`
	Server    string `json:"server"`
	Generator string `json:"generator"`
	DBType    string `json:"dbtype"`
	DBVersion string `json:"dbversion"`
	Skin      string `json:"skin"`
}

// Extension holds a single loaded extension entry.
type Extension struct {
	Name string `json:"name"`
}

// Namespace holds a single namespace entry.
type Namespace struct {
	ID        int    `json:"id"`
	Name      string `json:"*"`
	Canonical string `json:"canonical"`
}

// Skin holds a single skin entry.
type Skin struct {
	Code    string `json:"code"`
	Default *bool  `json:"default,omitempty"`
}
