package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
)

var Reset = "\033[0m"
var Red = "\033[31m"
var Green = "\033[32m"
var Yellow = "\033[33m"
var Gray = "\033[37m"
var Blue = "\033[34m"
var Purple = "\033[35m"
var Cyan = "\033[36m"
var HighIntensityCyan = "\033[96m"
var White = "\033[97m"

func setUpProcess(ctx context.Context, name string, color string, args ...string) error {
	prefix := fmt.Sprintf("%s[%s] >> ", color, name)
	suffix := fmt.Sprintf("%s\n", Reset)
	fmt.Printf("%s STARTING UP%s", prefix, suffix)
	cmdArgs := []string{"run"}
	cmdArgs = append(cmdArgs, args...)
	cmd := exec.CommandContext(ctx, "go", cmdArgs...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		fmt.Printf("%s%s%s%s", prefix, Red, err, suffix)
		return err
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		fmt.Printf("%s%s%s%s", prefix, Red, err, suffix)
		return err
	}

	in := bufio.NewScanner(stdout)
	err = cmd.Start()
	if err != nil {
		fmt.Printf("%s%s%s%s", prefix, Red, err, suffix)
		return err
	}

	go func() {
		for in.Scan() {
			fmt.Printf("%s%s%s", prefix, in.Text(), suffix)
		}
		if err := in.Err(); err != nil {
			fmt.Printf("%s%s%s%s", prefix, Red, err, suffix)
		}
	}()

	inErr := bufio.NewScanner(stderr)
	go func() {
		for inErr.Scan() {
			fmt.Printf("%s%s%s", prefix, inErr.Text(), suffix)
		}
		if err := inErr.Err(); err != nil {
			fmt.Printf("%s%s%s%s", prefix, Red, err, suffix)
		}
	}()

	go func() {
		err = cmd.Wait()
		fmt.Printf("%s%sQUIT UNEXPECTEDLY: %s%s", prefix, Red, err, suffix)
	}()
	return nil
}

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		defer cancel()
		c := make(chan os.Signal, 1)
		signal.Notify(c, os.Interrupt)
		<-c
		os.Exit(0)
	}()

	err := setUpProcess(ctx, "turboscansvc", Green, "./cmd/turboscan", "service", "start", "turboscansvc")
	if err != nil {
		return
	}
	err = setUpProcess(ctx, "hydrosvc", Yellow, "./cmd/turboscan", "service", "start", "hydrosvc")
	if err != nil {
		return
	}
	err = setUpProcess(ctx, "reposvc", Gray, "./cmd/reposvc/main.go")
	if err != nil {
		return
	}
	err = setUpProcess(ctx, "workflowsvc", Blue, "./cmd/workflowsvc/main.go")
	if err != nil {
		return
	}
	err = setUpProcess(ctx, "analysistriggersvc", Purple, "cmd/analysistriggersvc/main.go")
	if err != nil {
		return
	}
	err = setUpProcess(ctx, "codeqltelemetryprocessorsvc", HighIntensityCyan, "cmd/codeqltelemetryprocessorsvc/main.go")
	if err != nil {
		return
	}
	err = setUpProcess(ctx, "alertlinkprocessorsvc", Cyan, "./cmd/turboscan", "service", "start", "alertlinkprocessorsvc")
	if err != nil {
		return
	}
	err = setUpProcess(ctx, "aqueductsvc", White, "cmd/aqueductsvc/main.go")
	if err != nil {
		return
	}

	select {}
}
