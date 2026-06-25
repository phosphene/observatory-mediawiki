Feature: Database Invariants
  In order to prove state is correctly written to the data layer
  As a platform engineer
  I need to verify the database schema and content directly

  Background:
    Given the Observatory stack is running
    And the database connection is established

  Scenario: Core MediaWiki schema is installed
    Then the "page" table should exist in the database
    And the "revision" table should exist in the database
    And the "user" table should exist in the database
    And the "site_stats" table should exist in the database

  Scenario: SemanticMediaWiki schema is installed
    Then the "smw_object_ids" table should exist in the database

  Scenario: MediaWiki is installed with at least one page
    Then the page count should be at least 1
