.PHONY: test lint coverage clean

test:
	go test -v ./test/...

coverage:
	go test -v -coverprofile=coverage.out ./test/...
	go tool cover -func=coverage.out
	go tool cover -html=coverage.out -o coverage.html

lint:
	golangci-lint run ./...

clean:
	rm -f coverage.out coverage.html
	go clean -testcache
