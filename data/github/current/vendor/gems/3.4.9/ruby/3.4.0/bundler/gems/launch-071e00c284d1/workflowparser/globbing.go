package workflowparser

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	errors2 "github.com/pkg/errors"
)

type BadGlobError struct {
	message string
}

func (e BadGlobError) Error() string {
	return fmt.Sprintf(e.message)
}

func NewBadGlobError(format string, args ...any) BadGlobError {
	if len(args) == 0 {
		return BadGlobError{
			message: format,
		}
	}
	return BadGlobError{message: fmt.Sprintf(format, args...)}
}

const wholeDiffGlobMaxDuration = time.Second * 5
const singleGlobPathMaxDuration = time.Millisecond * 250

func MatchGlobs(spec *GlobFilterSpec, input []string) (bool, error) {
	// if we have no globs, that's a match
	if len(spec.Sequence) == 0 {
		return true, nil
	}

	r := runOperationWithTimeout(func() opResult {
		gs, err := CompileV2Globs(spec.Sequence)
		if err != nil {
			return opResult{err: err}
		}
		ok, err := runGlobSequenceVsMany(gs, input, spec.IsInclude)
		return opResult{result: ok, err: err}
	}, wholeDiffGlobMaxDuration, totalDiffRuntimeExceededError{})

	return r.result, r.err
}

// runs a sequence of globs as either an include (looking for 1+ matched),
// or exclude (looking for 1+ not matched)
func runGlobSequenceVsMany(globs []Glob, inputs []string, isInclusive bool) (bool, error) {
	for _, path := range inputs {
		included, err := runGlobSequence(globs, path)
		if err != nil {
			return false, err
		}
		if included == isInclusive {
			return true, nil
		}
	}
	return false, nil
}

func runGlobSequence(globs []Glob, input string) (bool, error) {
	included := false
	for _, glob := range globs {
		r := matchWithTimeout(input, glob)
		if r.err != nil {
			return false, r.err
		}
		// a negated match switches us away from included
		if glob.IsNegative() {
			if r.result {
				included = false
			}
		} else if r.result {
			// whereas a normal match, switches us to included
			included = true
		}
	}
	return included, nil
}

func matchWithTimeout(input string, glob Glob) opResult {
	return runOperationWithTimeout(func() opResult {
		ok := glob.Match(input)
		return opResult{result: ok, err: nil}
	}, singleGlobPathMaxDuration, globRuntimeExceededError{glob: glob.Raw()})
}

type opResult struct {
	result bool
	err    error
}

func runOperationWithTimeout(boolOp func() opResult, duration time.Duration, timeoutErr error) opResult {
	done := make(chan opResult, 1)

	go (func() {
		done <- boolOp()
	})()

	select {
	case r := <-done:
		return r
	case <-time.After(duration):
		return opResult{err: timeoutErr, result: false}
	}
}

type Glob interface {
	Match(s string) bool
	IsNegative() bool
	// raw text
	Raw() string
}

type glob struct {
	re         regexp.Regexp
	raw        string
	isNegative bool
}

func (g *glob) Raw() string {
	return g.raw
}

func (g *glob) IsNegative() bool {
	return g.isNegative
}

func (g *glob) Match(input string) bool {
	return g.re.MatchString(input)
}

type globScanner struct {
	input string
}

func (s *globScanner) atEnd() bool {
	return s.input == ""
}

func (s *globScanner) scan(re *regexp.Regexp) (string, bool) {
	match := re.FindStringSubmatch(s.input)
	if match == nil {
		return "", false
	}
	s.advance(len(match[0]))
	return match[0], true
}

func (s *globScanner) takeString(t string) bool {
	if !strings.HasPrefix(s.input, t) {
		return false
	}
	s.advance(len(t))
	return true
}

func (s *globScanner) isNext(next string) bool {
	return strings.HasPrefix(s.input, next)
}

func (s *globScanner) advance(i int) {
	s.input = s.input[i:]
}

func (s *globScanner) takeOne() string {
	// *must* be called after checking atEnd()
	o := s.input[0:1]
	s.advance(1)
	return o
}

var (
	starsRE         = regexp.MustCompile(`^\*+`)
	questionMarksRE = regexp.MustCompile(`^\?+`)
	plussesRE       = regexp.MustCompile(`^\++`)
	rangeContentRE  = regexp.MustCompile(`^[^\]]+`)
	// optional ^, followed by individual, or ranges of, digits or a-z characters
	validRangeContentRE = regexp.MustCompile(`(?i)^\^?(?:(?:\d(?:-\d)?)|(?:[a-z](?:-[a-z])?))+$`)
	escapeRE            = regexp.MustCompile(`^\\(?:.)?`)
)

var (
	errTooManyStars               = errors.New("too many sequential * characters")
	errPlusAfterStar              = errors.New("+ cannot follow *")
	errTooManyPlusses             = errors.New("+ cannot follow +")
	errTooManyQuestions           = errors.New("? cannot follow ?")
	errQuestionAfterStar          = errors.New("? cannot follow *")
	errQuestionAfterPlus          = errors.New("? cannot follow +")
	errUnterminatedCharacterRange = errors.New("unterminated character range")
	errInvalidCharacterRange      = errors.New("invalid character range")
	errInvalidGlobV2              = errors.New("invalid glob")
	errTrailingBackslash          = errors.New("trailing backslash")
)

func CompileV2Globs(raw []string) ([]Glob, error) {
	gs := make([]Glob, 0, len(raw))
	failures := make([]string, 0)
	for _, r := range raw {
		g, err := compileGlobV2(r)
		if err == nil {
			gs = append(gs, g)
		} else {
			failures = append(failures, r)
		}
	}
	if len(failures) > 0 {
		return nil, NewBadGlobError(strings.Join(failures, ", "))
	}
	return gs, nil
}

// compileGlobV2 takes an input string in our globbing language and compiles
// it to a Go regexp that implements it.
func compileGlobV2(input string) (*glob, error) {
	withoutNegation := strings.TrimPrefix(input, "!")
	isNegation := false
	if input != withoutNegation {
		isNegation = true
	}
	scanner := globScanner{input: withoutNegation}
	output := strings.Builder{}
	for !scanner.atEnd() {
		if escape, ok := scanner.scan(escapeRE); ok {
			if escape == `\` {
				return nil, errTrailingBackslash
			}
			output.WriteString(escape)
			continue
		}

		if globs, ok := scanner.scan(starsRE); ok {
			switch len(globs) {
			case 2:
				output.WriteString(".*")
				if scanner.isNext("/") {
					scanner.advance(1)
				}
			case 1:
				output.WriteString("[^/]*")
			default:
				return nil, errTooManyStars
			}
			if scanner.isNext("+") {
				return nil, errPlusAfterStar
			}
			if scanner.isNext("?") {
				return nil, errQuestionAfterStar
			}
			continue
		}

		if optional, ok := scanner.scan(questionMarksRE); ok {
			if len(optional) > 1 {
				return nil, errTooManyQuestions
			}
			output.WriteString("?")
			continue
		}

		if reptition, ok := scanner.scan(plussesRE); ok {
			if len(reptition) > 1 {
				return nil, errTooManyPlusses
			}
			if scanner.isNext("?") {
				return nil, errQuestionAfterPlus
			}
			output.WriteString("+")
			continue
		}

		if scanner.takeString("[") {
			rangeContent, ok := scanner.scan(rangeContentRE)
			if !ok {
				return nil, errInvalidCharacterRange
			}
			if !scanner.takeString("]") {
				return nil, errUnterminatedCharacterRange
			}
			if !validRangeContentRE.MatchString(rangeContent) {
				return nil, errInvalidCharacterRange
			}
			// delegate to re to determine if ranges are valid, i.e not backwards
			rangeString := fmt.Sprintf("[%s]", rangeContent)
			if _, err := regexp.Compile(rangeString); err != nil {
				return nil, errInvalidCharacterRange
			}
			output.WriteString(rangeString)
			continue
		}

		output.WriteString(regexp.QuoteMeta(scanner.takeOne()))
	}
	expr := fmt.Sprintf("^%s$", output.String())
	re, err := regexp.Compile(expr)
	if err != nil {
		return nil, errInvalidGlobV2
	}
	return &glob{
		re:         *re,
		raw:        input,
		isNegative: isNegation,
	}, nil
}

type globRuntimeExceededError struct {
	glob string
}

func (g globRuntimeExceededError) Error() string {
	return "globRuntimeExceeded"
}

type totalDiffRuntimeExceededError struct {
}

func (t totalDiffRuntimeExceededError) Error() string {
	return "totalDiffRuntimeExceeded"
}

func WasSingleGlobTimeout(err error) (string, bool) {
	g, ok := errors2.Cause(err).(globRuntimeExceededError)
	if !ok {
		return "", false
	}
	return g.glob, true
}

func IsTotalDiffRuntime(err error) bool {
	_, ok := errors2.Cause(err).(totalDiffRuntimeExceededError)
	return ok
}
