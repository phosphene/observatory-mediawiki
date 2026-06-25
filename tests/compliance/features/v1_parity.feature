Feature: V1 Parity Contract
  In order to safely replace V1 in production
  As a platform engineer
  I need to verify that V2 is behaviorally equivalent to the V1 production baseline

  Background:
    Given the Observatory stack is running
    And the V1 baseline is loaded

  Scenario: Site identity matches V1
    When I request the MediaWiki API siteinfo
    Then the sitename should be "The Observatory"
    And the database type should be "mysql"
    And the database version should be "8.4.0"

  Scenario: All V1 extensions are loaded
    When I request the loaded extensions
    Then all V1 baseline extensions should be present
    And the extension count should be at least 75

  Scenario: All V1 custom namespaces are present
    When I request the site namespaces
    Then all V1 baseline namespaces should be present with correct names

  Scenario: Default skin is known and documented
    When I request the loaded skins
    Then the default skin should be "chameleon" or a known divergence
