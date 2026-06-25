// Package db provides direct MySQL access for data invariant verification.
// Follows the reference pattern: prove state in the data layer, not just HTTP.
package db

import (
	"context"
	"database/sql"
	"fmt"

	_ "github.com/go-sql-driver/mysql"
)

// Client wraps a *sql.DB for Observatory-specific queries.
type Client struct {
	db *sql.DB
}

// NewClient opens a MySQL connection to host:port with the given credentials.
func NewClient(host, port, user, password, dbname string) (*Client, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true",
		user, password, host, port, dbname)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("db.NewClient: %w", err)
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("db.NewClient ping: %w", err)
	}
	return &Client{db: db}, nil
}

// Close closes the underlying connection.
func (c *Client) Close() error {
	return c.db.Close()
}

// NamespaceExists returns true if the given namespace ID exists in the MW page table.
func (c *Client) NamespaceExists(ctx context.Context, nsID int) (bool, error) {
	var count int
	err := c.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM page WHERE page_namespace = ? LIMIT 1`, nsID,
	).Scan(&count)
	if err != nil {
		return false, fmt.Errorf("NamespaceExists(%d): %w", nsID, err)
	}
	return count > 0, nil
}

// TableExists returns true if the given table exists in the DB.
func (c *Client) TableExists(ctx context.Context, table string) (bool, error) {
	var name string
	err := c.db.QueryRowContext(ctx,
		`SELECT table_name FROM information_schema.tables
		 WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1`, table,
	).Scan(&name)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("TableExists(%s): %w", table, err)
	}
	return true, nil
}

// SMWPropertyCount returns the number of SMW property rows — proves SMW schema installed.
func (c *Client) SMWPropertyCount(ctx context.Context) (int, error) {
	var count int
	err := c.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM smw_object_ids WHERE smw_namespace = 102 LIMIT 1`,
	).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("SMWPropertyCount: %w", err)
	}
	return count, nil
}

// PageCount returns the total number of pages in the wiki.
func (c *Client) PageCount(ctx context.Context) (int, error) {
	var count int
	err := c.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM page`).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("PageCount: %w", err)
	}
	return count, nil
}
