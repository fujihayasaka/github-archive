package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

type cronjobConfig struct {
	ApiVersion string `json:"apiVersion" yaml:"apiVersion"`
	Kind       string `json:"kind" yaml:"kind"`
	Metadata   struct {
		Name string `json:"name" yaml:"name"`
	} `json:"metadata" yaml:"metadata"`
	Spec struct {
		Schedule    string
		Suspend     bool
		JobTemplate struct {
			Spec struct {
				Template struct {
					Spec struct {
						Containers []struct {
							Name    string   `json:"name" yaml:"name"`
							Image   string   `json:"image" yaml:"image"`
							Command []string `json:"command" yaml:"command"`
						} `json:"containers" yaml:"containers"`
					} `json:"spec" yaml:"spec"`
				} `json:"template" yaml:"template"`
			} `json:"spec" yaml:"spec"`
		} `json:"jobTemplate" yaml:"jobTemplate"`
	} `json:"spec" yaml:"spec"`
}

func main() {
	jankyBuild := flag.Bool("janky", false, "enable janky build")
	flag.Parse()

	args := flag.Args()
	if len(args) == 0 {
		log.Fatal("no arguments provided")
	}
	failed := false
	// the int in the map represents the line number of the `command` key in the yaml file
	failedFiles := make(map[string]int)
	for _, fileName := range args {
		fmt.Printf("checking %s\n", fileName)
		file, err := os.ReadFile(fileName)
		if err != nil {
			log.Fatalf("failed to open file: %v", err)
		}
		config := &cronjobConfig{}
		if err := yaml.Unmarshal(file, config); err != nil {
			fmt.Fprintf(os.Stderr, "failed to decode yaml: %v\n", err)
		}
		for _, container := range config.Spec.JobTemplate.Spec.Template.Spec.Containers {
			for _, command := range container.Command {
				if strings.HasPrefix(command, "-") && !strings.HasPrefix(command, "--") {
					fmt.Fprintf(os.Stderr, "flag %[1]s in %[2]s should be prefixed with -- so that it reads -%[1]s\n", command, container.Name)
					failed = true
					if _, ok := failedFiles[fileName]; !ok {
						failedFiles[fileName] = findUsageLine(file, command)
					}
				}
			}
		}
	}
	if failed {
		for filename, lineNumber := range failedFiles {
			if *jankyBuild {
				fmt.Printf(`===CHECK RUN ANNOTATION===
{
	"title": "Non GNU-style flags detected",
	"annotation_level": "failure",
	"path": "%s",
	"start_line": %d,
	"end_line": %d,
	"message": "Usage of single dashed flag detected, please ensure you use double dashed flags in configurations."
}
===END CHECK RUN ANNOTATION===
`, strings.TrimPrefix(filename, "./"), lineNumber+1, lineNumber+1)
			}
			fmt.Printf("::error file=%s,line=%d,title=Non GNU-style flags detected::Usage of single dashed flag detected, please ensure you use double dashed flags in configurations.\n", strings.TrimPrefix(filename, "./"), lineNumber+1)
		}
		os.Exit(1)
	}
}

func findUsageLine(file []byte, argument string) int {
	lines := strings.Split(string(file), "\n")
	for i, line := range lines {
		if strings.Contains(line, argument) {
			return i
		}
	}
	return -1
}
