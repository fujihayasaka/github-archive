package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var (
	useLast = flag.Bool("last", false, "Use the last modified action log file")
)

func main() {
	flag.Parse()

	ctx := context.Background()

	if err := run(ctx); err != nil {
		log.Fatal(err)
	}
}

func run(ctx context.Context) error {
	wd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get working directory: %w", err)
	}

	actionLogsDir := filepath.Join(wd, "script", "actions-runner", "_diag")
	if _, err := os.Stat(actionLogsDir); os.IsNotExist(err) {
		return fmt.Errorf("action logs directory does not exist, make sure you run this from sweagentd root: %s", actionLogsDir)
	}

	return newActionsLogWatcher(actionLogsDir, *useLast).Start(ctx)
}

type actionsLogWatcher struct {
	dir     string
	useLast bool
}

func newActionsLogWatcher(dir string, useLast bool) *actionsLogWatcher {
	return &actionsLogWatcher{dir: dir, useLast: useLast}
}

func (w *actionsLogWatcher) Start(ctx context.Context) error {
	log.Printf("Starting to watch action logs in directory: %s, useLast: %v", w.dir, w.useLast)

	tick := time.NewTicker(5 * time.Second)
	defer tick.Stop()

	newFile, err := w.checkForNewLogs()
	if err != nil {
		return fmt.Errorf("error checking for new logs: %w", err)
	}

	if w.useLast && newFile != "" {
		log.Printf("Using last modified action log file: %s", newFile)
		return w.tail(ctx, newFile)
	}

WatchLoop:
	for {
		select {
		case <-ctx.Done():
			log.Println("Stopping action logs watcher")
			return nil
		case <-tick.C:
			log.Println("No action log file found, checking again...")
			foundFile, err := w.checkForNewLogs()
			if err != nil {
				return fmt.Errorf("error checking for new logs: %w", err)
			}

			log.Printf("Checked for new logs, found: %s", foundFile)
			if foundFile != "" && foundFile != newFile {
				log.Printf("New action log file detected: %s", foundFile)
				newFile = foundFile
				break WatchLoop
			}
		}
	}

	log.Printf("New action log file detected: %s", newFile)
	return w.tail(ctx, newFile)
}

func (w *actionsLogWatcher) Write(p []byte) (n int, err error) {
	var clean []string

	webConsolePrefix := "Enqueue web console line queue:"
	lines := strings.SplitSeq(string(p), "\n")
	for line := range lines {
		if !strings.Contains(line, webConsolePrefix) {
			continue
		}

		_, after, ok := strings.Cut(line, webConsolePrefix)
		if ok {
			clean = append(clean, strings.TrimSpace(after))
			continue
		}

		clean = append(clean, line)
	}

	// If nothing matched in this chunk, don't print anything
	if len(clean) == 0 {
		return len(p), nil
	}

	// Join lines and make sure there's a newline at the end
	out := strings.Join(clean, "\n") + "\n"

	if _, err := os.Stdout.Write([]byte(out)); err != nil {
		fmt.Fprintln(os.Stderr, "Error writing to stdout:", err)
		return 0, err
	}

	return len(p), nil
}

func (w *actionsLogWatcher) tail(ctx context.Context, filePath string) error {
	log.Printf("Tailing log file: %s", filePath)

	cmd := exec.CommandContext(ctx, "sh", "-c", "tail -f -n +1 "+filePath)
	cmd.Stdout = w
	cmd.Stderr = w

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start tail command: %w", err)
	}

	return cmd.Wait()
}

type fileEntry struct {
	filename string
	modtime  time.Time
}

func (w *actionsLogWatcher) checkForNewLogs() (string, error) {
	entries, err := os.ReadDir(w.dir)
	if err != nil {
		return "", fmt.Errorf("failed to read action logs directory: %w", err)
	}

	var logFiles []fileEntry
	for _, entry := range entries {
		filename := entry.Name()
		if !entry.IsDir() && strings.HasPrefix(filename, "Worker_") {
			info, err := entry.Info()
			if err != nil {
				return "", fmt.Errorf("failed to get file info for %s: %w", filename, err)
			}

			logFiles = append(logFiles, fileEntry{filename, info.ModTime()})
		}
	}

	if len(logFiles) > 0 {
		sort.Slice(logFiles, func(i, j int) bool {
			return logFiles[i].modtime.Before(logFiles[j].modtime)
		})

		latestFile := logFiles[len(logFiles)-1]
		return filepath.Join(w.dir, latestFile.filename), nil
	}

	return "", nil
}
