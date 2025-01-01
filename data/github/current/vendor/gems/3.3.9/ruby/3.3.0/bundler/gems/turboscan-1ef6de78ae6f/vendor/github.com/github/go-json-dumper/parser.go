package jsondumper

import (
	"bufio"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"
)

// A single line of the Go test JSON output.
// Each line is a separate JSON object.
// Defined in https://golang.org/cmd/test2json/
type goTestEvent struct {
	Time    time.Time // encodes as an RFC3339-format string
	Action  string
	Package string
	Test    string
	Elapsed float64 // seconds
	Output  string
}

// ===FAILURE===
// {
//   "suite": "FlakeTest",
//   "name": "test_queries_for_related_test_failures",
//   "areas_of_responsibility": [

//   ],
//   "areas_of_responsibility_error": "No #areas_of_responsibility method for FlakeTest",
//   "message": "Expected: true\n  Actual: false",
//   "location": "/Users/mistydemeo/github/ci/test/models/flake_test.rb:39",
//   "duration": 0.026078969007357955,
//   "fingerprint": "9545593415283c17f42a06c5fcce6377",
//   "hostname": "C02R70KCFVH8"
// }
// ===END FAILURE===
type goTestFailure struct {
	Suite                      string   `json:"suite"`
	Name                       string   `json:"name"`
	AreasOfResponsibility      []string `json:"areas_of_responsibility"`
	AreasOfResponsibilityError string   `json:"areas_of_responsibility_error"`
	ExceptionClass             string   `json:"exception_class"`
	Message                    string   `json:"message"`
	Location                   string   `json:"location"`
	Duration                   float64  `json:"duration"`
	Fingerprint                string   `json:"fingerprint"`
	Hostname                   string   `json:"hostname"`

	failure   bool
	startTime time.Time
	endTime   time.Time
}

func parseGoTestJSON(in io.Reader, teeWriter io.Writer) ([]goTestFailure, error) {
	tests := map[string]*goTestFailure{}

	scanner := bufio.NewScanner(in)
	for scanner.Scan() {
		line, err := parseGoTestJSONLine(scanner.Text())
		if err != nil {
			return nil, err
		}

		if len(line.Test) == 0 {
			continue
		}

		identifier := line.Package + "." + line.Test
		if _, ok := tests[identifier]; !ok {
			tests[identifier] = &goTestFailure{
				ExceptionClass:        "Error",
				AreasOfResponsibility: []string{},
			}
		}

		// run    - the test has started running
		// pause  - the test has been paused
		// cont   - the test has continued running
		// pass   - the test passed
		// bench  - the benchmark printed log output but did not fail
		// fail   - the test or benchmark failed
		// output - the test printed output
		// skip   - the test was skipped or the package contained no tests
		switch line.Action {
		case "run":
			tests[identifier].Suite = line.Package
			tests[identifier].Name = line.Test
			tests[identifier].startTime = line.Time
		case "output":
			if teeWriter != nil {
				teeWriter.Write([]byte(line.Output))
			}
			tests[identifier].Message = tests[identifier].Message + line.Output
			if file := parseLocationFromMessage(line.Output); file != "" {
				tests[identifier].Location = file
			}
		case "fail":
			tests[identifier].failure = true
			tests[identifier].endTime = line.Time
			tests[identifier].Duration = tests[identifier].endTime.Sub(tests[identifier].startTime).Seconds()
			if tests[identifier].Location != "" {
				tests[identifier].Location = strings.TrimPrefix(line.Package, "github.com/github") + "/" + tests[identifier].Location
			}
			tests[identifier].Fingerprint = generateFingerprint(tests[identifier])
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	hostname, _ := os.Hostname()

	failures := []goTestFailure{}
	for _, failure := range tests {
		if failure.failure {
			failure.Hostname = hostname
			failures = append(failures, *failure)
		}
	}

	sort.SliceStable(failures, func(i, j int) bool {
		if failures[i].Suite == failures[j].Suite {
			return failures[i].Name < failures[j].Name
		}
		return failures[i].Suite < failures[j].Suite
	})

	return failures, nil
}

// https://golang.org/cmd/test2json/
func parseGoTestJSONLine(text string) (goTestEvent, error) {
	line := &goTestEvent{}
	err := json.Unmarshal([]byte(text), line)
	return *line, err
}

func generateFingerprint(test *goTestFailure) string {
	hash := sha256.New()
	fmt.Fprint(hash, test.Suite)
	fmt.Fprint(hash, "|")
	fmt.Fprint(hash, test.Name)
	fmt.Fprint(hash, "|")
	if test.Location != "" {
		fmt.Fprint(hash, test.Location)
	} else {
		fmt.Fprint(hash, test.Message)
	}
	return fmt.Sprintf("%x", hash.Sum(nil))
}

var locationParser = regexp.MustCompile(`^\s+(\S+:\d+):`)

func parseLocationFromMessage(message string) string {
	// === RUN   TestThisFunctionFailsItsTests\n    failure_test.go:11: This function has failed.\n--- FAIL: TestThisFunctionFailsItsTests (0.00s)\n
	matches := locationParser.FindAllStringSubmatch(message, -1)
	if len(matches) == 0 || len(matches[0]) <= 1 {
		return ""
	}
	return matches[0][1]
}
