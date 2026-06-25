Feature: Taqasta Boot Contract
  In order to guarantee a correct V2 deployment
  As a platform engineer
  I need to verify that the container boots with an intact configuration chain

  Scenario: MediaWiki API is reachable and healthy
    Given the Observatory stack is running
    When I request the MediaWiki API siteinfo
    Then the API response should be valid JSON
    And the API response should contain a "query" key

  Scenario: Main page renders without raw Lua invocations
    Given the Observatory stack is running
    When I request "/wiki/Main_Page"
    Then the response status should be 200
    And the response body should not contain "{{#invoke"

  Scenario: robots.txt is served with correct directives
    Given the Observatory stack is running
    When I request "/robots.txt"
    Then the response status should be 200
    And the response body should contain "User-agent"

  Scenario: Favicon is served from webroot
    Given the Observatory stack is running
    When I request "/favicon.ico"
    Then the response status should be 200
