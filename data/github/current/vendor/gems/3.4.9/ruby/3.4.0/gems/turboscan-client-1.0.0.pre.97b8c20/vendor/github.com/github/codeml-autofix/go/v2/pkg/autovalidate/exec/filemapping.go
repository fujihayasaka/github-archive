package exec

import (
	"errors"
	"fmt"
	"os"
	"path"
	"strings"
)

// MappingDirection declares whether a mapping is used as input, output, or both.
type MappingDirection uint8

const (
	// MappingInput indicates the mapping is used as input.
	MappingInput MappingDirection = 1 << iota
	// MappingOutput indicates the mapping is used as output.
	MappingOutput
)

// IsInput returns true when the direction includes input.
func (d MappingDirection) IsInput() bool { return d&MappingInput != 0 }

// IsOutput returns true when the direction includes output.
func (d MappingDirection) IsOutput() bool { return d&MappingOutput != 0 }

// FileMappingSpec is a tagged interface representing one of the mapping specification variants.
// Variants:
//   - BytesSpec: inline bytes to materialize (input or input+output)
//   - HostPathSpec: host file/dir to mount (input or input+output)
//   - OutputSpec: an output-only file expected to be produced
type FileMappingSpec interface {
	LogicalPath() string
	Direction() MappingDirection
	isFileMappingSpec()
}

// BytesSpec represents in-memory bytes that will be written into the workspace.
type BytesSpec struct {
	logicalPath string
	data        []byte
	direction   MappingDirection // MappingInput or MappingInput|MappingOutput
}

// HostPathSpec represents a host path (file or directory) to be mounted.
type HostPathSpec struct {
	logicalPath string
	hostPath    string
	direction   MappingDirection // MappingInput or MappingInput|MappingOutput
}

// OutputSpec represents an output-only file.
type OutputSpec struct {
	logicalPath string
}

// Interface method implementations

// LogicalPath returns the logical path for the BytesSpec.
func (b BytesSpec) LogicalPath() string { return b.logicalPath }

// Direction returns the mapping direction for the BytesSpec.
func (b BytesSpec) Direction() MappingDirection { return b.direction }

// LogicalPath returns the logical path for the HostPathSpec.
func (h HostPathSpec) LogicalPath() string { return h.logicalPath }

// Direction returns the mapping direction for the HostPathSpec.
func (h HostPathSpec) Direction() MappingDirection { return h.direction }

// LogicalPath returns the logical path for the OutputSpec.
func (o OutputSpec) LogicalPath() string { return o.logicalPath }

// Direction returns the mapping direction for the OutputSpec (always output).
func (o OutputSpec) Direction() MappingDirection { return MappingOutput }
func (BytesSpec) isFileMappingSpec()             {}
func (HostPathSpec) isFileMappingSpec()          {}
func (OutputSpec) isFileMappingSpec()            {}

// FileMapping maps logical paths to their specs.
type FileMapping map[string]FileMappingSpec

// FileMappingBuilder provides a fluent API to assemble a FileMapping safely.
type FileMappingBuilder struct {
	specs []FileMappingSpec
	// no error accumulation; validation happens in Build
}

// NewFileMappingBuilder creates a new builder instance.
func NewFileMappingBuilder() *FileMappingBuilder { return &FileMappingBuilder{} }

// InBytes adds an input-only bytes file.
func (b *FileMappingBuilder) InBytes(logicalPath string, data []byte) *FileMappingBuilder {
	return b.add(BytesSpec{logicalPath: logicalPath, data: data, direction: MappingInput})
}

// InOutBytes adds a bytes file that is both input and output.
func (b *FileMappingBuilder) InOutBytes(logicalPath string, data []byte) *FileMappingBuilder {
	return b.add(BytesSpec{logicalPath: logicalPath, data: data, direction: MappingInput | MappingOutput})
}

// In adds a host path (input only).
func (b *FileMappingBuilder) In(logicalPath, hostPath string) *FileMappingBuilder {
	return b.add(HostPathSpec{logicalPath: logicalPath, hostPath: hostPath, direction: MappingInput})
}

// InOut adds a host path used for both input and output.
func (b *FileMappingBuilder) InOut(logicalPath, hostPath string) *FileMappingBuilder {
	return b.add(HostPathSpec{logicalPath: logicalPath, hostPath: hostPath, direction: MappingInput | MappingOutput})
}

// Out adds an output-only file.
func (b *FileMappingBuilder) Out(logicalPath string) *FileMappingBuilder {
	return b.add(OutputSpec{logicalPath: logicalPath})
}

func (b *FileMappingBuilder) add(spec FileMappingSpec) *FileMappingBuilder {
	if b != nil {
		b.specs = append(b.specs, spec)
	}
	return b
}

// Build finalizes and returns the FileMapping or an error if invalid relationships exist.
// Rules:
//   - Allowed: adding files under a mapped directory (directory represented by HostPathSpec).
//   - Disallowed: adding a mapping whose path shadows existing deeper paths if the mapping is not a directory (BytesSpec/OutputSpec).
//   - Disallowed: adding a deeper mapping under a path already mapped as a non-directory (BytesSpec/OutputSpec).
func (b *FileMappingBuilder) Build() (FileMapping, error) {
	if b == nil {
		return nil, fmt.Errorf("builder is nil")
	}

	// treeNode represents a node in the logical path tree. A node may have
	// an attached spec (mapping for that exact path) and/or children (deeper paths).
	type treeNode struct {
		spec     FileMappingSpec
		children map[string]*treeNode
	}
	root := &treeNode{children: map[string]*treeNode{}}

	// Cache hostPath -> isDir for HostPathSpec lookups to avoid repeated os.Stat calls.
	dirCache := map[string]bool{}
	isDirLike := func(spec FileMappingSpec) bool {
		if hs, ok := spec.(HostPathSpec); ok {
			if v, found := dirCache[hs.hostPath]; found {
				return v
			}
			info, err := os.Stat(hs.hostPath)
			if err != nil {
				// If the path does not exist yet, treat it as non-directory so that adding nested mappings will trigger validation errors.
				dirCache[hs.hostPath] = false
				return false
			}
			isDir := info.IsDir()
			dirCache[hs.hostPath] = isDir
			return isDir
		}
		return false
	}

	var errs []error

	for _, s := range b.specs {
		lp := s.LogicalPath()
		if lp == "" { // empty logical paths not supported
			errs = append(errs, fmt.Errorf("empty logical path is invalid"))
			continue
		}
		// Preserve prior validation: flag consecutive slashes explicitly.
		if strings.Contains(lp, "//") {
			errs = append(errs, fmt.Errorf("invalid empty path component in '%s'", lp))
			continue
		}
		clean := path.Clean(lp) // use POSIX-style cleaning (we want forward slashes regardless of host OS for logical paths)
		if clean == "." {       // path.Clean returns "." for empty / current dir references
			errs = append(errs, fmt.Errorf("invalid logical path '.' derived from '%s'", lp))
			continue
		}
		// Remove any leading './'
		clean = strings.TrimPrefix(clean, "./")
		comps := strings.Split(clean, "/")
		cur := root
		var prefixParts []string
		for _, c := range comps {
			prefixParts = append(prefixParts, c)
			if cur.spec != nil && !isDirLike(cur.spec) {
				errs = append(errs, fmt.Errorf("cannot map '%s' under non-directory mapping '%s'", clean, strings.Join(prefixParts[:len(prefixParts)-1], "/")))
				cur = nil
				break
			}
			if cur.children == nil {
				cur.children = map[string]*treeNode{}
			}
			next := cur.children[c]
			if next == nil {
				next = &treeNode{}
				cur.children[c] = next
			}
			cur = next
		}
		if cur == nil {
			continue
		}
		if cur.spec != nil { // duplicate exact path
			errs = append(errs, fmt.Errorf("duplicate logical mapping path: %s (first: %T, second: %T)", clean, cur.spec, s))
			continue
		}
		if len(cur.children) > 0 && !isDirLike(s) {
			errs = append(errs, fmt.Errorf("mapping '%s' shadows nested path(s) but is not directory-like", clean))
			continue
		}
		cur.spec = s
	}

	if len(errs) > 0 {
		return nil, combineErrors(errs)
	}

	// Extract mapping by DFS.
	fm := make(FileMapping)
	var stack []struct {
		path string
		node *treeNode
	}
	stack = append(stack, struct {
		path string
		node *treeNode
	}{"", root})
	for len(stack) > 0 {
		n := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if n.node.spec != nil {
			p := strings.TrimPrefix(n.path, "/")
			if p != "" {
				fm[p] = n.node.spec
			}
		}
		for name, child := range n.node.children {
			var childPath string
			if n.path == "" {
				childPath = "/" + name
			} else {
				childPath = n.path + "/" + name
			}
			stack = append(stack, struct {
				path string
				node *treeNode
			}{childPath, child})
		}
	}
	return fm, nil
}

// combineErrors aggregates multiple errors into one.
func combineErrors(errs []error) error {
	if len(errs) == 1 {
		return errs[0]
	}
	var b strings.Builder
	_, _ = b.WriteString("multiple errors:\n")
	for _, e := range errs {
		_, _ = b.WriteString(" - ")
		_, _ = b.WriteString(e.Error())
		_, _ = b.WriteString("\n")
	}
	return errors.New(b.String())
}
