// Usage: go run _template/docs/fixlinks.go gen/docs
//
// This program is normally only called by script/generate-docs.
// It assumes that gen/docs has index.csv and a bunch of markdown files.
package main

import (
	"bufio"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"path"
	"regexp"
	"strings"
)

func main() {
	dir := os.Args[1]
	//fmt.Printf("DIR: %q\n", dir)

	indexFilename := path.Join(dir, "index.csv")
	index, err := readIndex(indexFilename)
	if err != nil {
		fmt.Printf("fatal: %s: %v\n", indexFilename, err)
		os.Exit(1)
	}

	for _, filename := range allMDs(dir) {
		if err := fixLinks(dir, filename, index); err != nil {
			fmt.Printf("error: %s: %v\n", filename, err)
		}
	}
}

func fixLink(root, filename, link string, index index) string {
	linkTargetStart := strings.Index(link, "(")
	if linkTargetStart == -1 {
		panic(fmt.Sprintf("error: %q is not a link", link))
	}
	linkTarget := strings.Trim(link[linkTargetStart:], "()")

	if linkTarget[0] != '#' {
		panic(fmt.Sprintf("error: %q should be link to anchor", link))
	}
	anchor := linkTarget[1:]

	if targetProtoFile, ok := index.typeToFile[anchor]; ok {
		targetMDFile := strings.Replace(targetProtoFile, ".proto", ".md", 1)
		fullTargetMDFile := path.Join(root, targetMDFile)
		if fullTargetMDFile != filename {
			link = fmt.Sprintf("%s(%s#%s)", link[:linkTargetStart], relPath(fullTargetMDFile, filename), anchor)
		}
	} else if strings.HasPrefix(anchor, "google.protobuf.") {
		const protobufURL = "https://developers.google.com/protocol-buffers/docs/reference/google.protobuf"
		link = fmt.Sprintf("%s(%s#%s)", link[:linkTargetStart], protobufURL, anchor)
	} else {
		// This is probably a scalar type, link to protobuf docs.
		const scalarTypesURL = "https://developers.google.com/protocol-buffers/docs/proto3#scalar"
		link = fmt.Sprintf("%s(%s)", link[:linkTargetStart], scalarTypesURL)
	}

	return link
}

func relPath(target, source string) string {
	targetParts := strings.Split(target, "/")
	sourceParts := strings.Split(source, "/")
	sourceParts = sourceParts[:len(sourceParts)-1]

	for len(targetParts) > 0 && len(sourceParts) > 0 && targetParts[0] == sourceParts[0] {
		targetParts = targetParts[1:]
		sourceParts = sourceParts[1:]
	}

	var resParts []string
	for range sourceParts {
		resParts = append(resParts, "..")
	}
	resParts = append(resParts, targetParts...)
	return strings.Join(resParts, "/")
}

var markdownLink = regexp.MustCompile(`\[.*?\]\(#.*?\)`)

func fixLinks(root, filename string, index index) error {
	content, err := ioutil.ReadFile(filename)
	if err != nil {
		return err
	}

	updated := markdownLink.ReplaceAllStringFunc(string(content), func(match string) string {
		return fixLink(root, filename, match, index)
	})

	return ioutil.WriteFile(filename, []byte(updated), 0644)
}

type index struct {
	typeToFile map[string]string
}

func readIndex(filename string) (index, error) {
	f, err := os.Open(filename)
	if err != nil {
		return index{}, err
	}

	var ret index
	ret.typeToFile = map[string]string{}

	r := bufio.NewReader(f)
	for {
		line, err := r.ReadString('\n')
		if err != nil && err != io.EOF {
			return index{}, err
		}
		record := strings.Split(strings.TrimSpace(line), ",")
		if len(record) >= 3 {
			switch record[1] {
			case "method":
				key := record[2] + "-" + record[3]
				ret.typeToFile[key] = record[0]
			default:
				ret.typeToFile[record[2]] = record[0]
			}
		}
		if err == io.EOF {
			return ret, nil
		}
	}
}

func allMDs(dirnames ...string) []string {
	var res []string

	for len(dirnames) > 0 {
		nextDir := dirnames[0]
		dirnames = dirnames[1:]

		entries, err := ioutil.ReadDir(nextDir)
		if err != nil {
			panic(fmt.Sprintf("%s: %v", nextDir, err))
		}

		for _, e := range entries {
			fullName := path.Join(nextDir, e.Name())
			if e.IsDir() {
				dirnames = append(dirnames, fullName)
			} else if strings.HasSuffix(e.Name(), ".md") {
				res = append(res, fullName)
			}
		}
	}

	return res
}
