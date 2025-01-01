# go-json-dumper

Hi there, Gopher! At GitHub, we use a CI system called Janky to make our testing fun and easy. It provides a neat way to display errors, but in order to use it a test system must output the correct data. This project aims to provide this special output for the native Go test suite.

## Usage

```console
# Install
$ export GOPRIVATE="github.com/github"
$ go get github.com/github/go-json-dumper/cmd/go-json-dumper
# Run your tests 
$ go test -json ./... | go-json-dumper -tee
```

That's all! If any failures exist, they will be output in a compliant format and go-json-dumper will exit with a non-zero exit code.

## Developing

Before changing go-json-dumper, add a commit to break a test & create a PR. Make sure you see the annotation in the PR (you'll need to actually change the test so it's in the diff) and should see Janky failing. This will help validate that every commit you push to modify go-json-dumper still outputs the correct data.
