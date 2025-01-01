package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

func versionFromFile(path string) uint {
	base := filepath.Base(path)

	var version uint
	var name string

	_, _ = fmt.Sscanf(base, "%d_%s.up.sql", &version, &name)

	return version
}

func updateNextTransition(dir WriteFileFS) error {
	matches, err := fs.Glob(dir, "*_*.up.sql")
	if err != nil {
		return err
	}

	if len(matches) < 2 {
		return nil
	}

	sort.Slice(matches, func(i, j int) bool {
		return versionFromFile(matches[i]) < versionFromFile(matches[j])
	})

	previous := matches[len(matches)-2]
	next := matches[len(matches)-1]

	previousData, err := fs.ReadFile(dir, previous)
	if err != nil {
		return err
	}

	scan := bufio.NewScanner(bytes.NewReader(previousData))
	for scan.Scan() {
		if strings.HasPrefix(scan.Text(), "-- next: ") {
			return fmt.Errorf("previous migration %q already has a next transition", filepath.Base(previous))
		}
	}

	return dir.WriteFile(previous, append([]byte(fmt.Sprintf("-- next: %d\n\n", versionFromFile(next))), previousData...), 0o644)
}

type WriteFileFS interface {
	fs.FS
	WriteFile(path string, data []byte, perm os.FileMode) error
}

type writeDirFS struct {
	fs.FS
	dir string
}

func WriteDirFS(dir string) WriteFileFS {
	return &writeDirFS{
		FS:  os.DirFS(dir),
		dir: dir,
	}
}

func (f writeDirFS) WriteFile(path string, data []byte, perm os.FileMode) error {
	return os.WriteFile(filepath.Join(f.dir, path), data, perm)
}

func do(dir WriteFileFS, pkgName, prefix, name string, createGHES func() bool) error {
	transition := fmt.Sprintf("%s_%s.go", prefix, name)
	pkgFile := fmt.Sprintf("%s.go", pkgName)

	if stat, err := fs.Stat(dir, "."); os.IsNotExist(err) || !stat.IsDir() {
		return fmt.Errorf("directory %q does not exist, use -dest to set output directory", pkgName)
	}

	if _, err := fs.Stat(dir, pkgFile); os.IsNotExist(err) {
		if err := dir.WriteFile(pkgFile, []byte(fmt.Sprintf("// Package migrations provides migrations and transitions.\npackage %s\n\nimport \"github.com/github/go-upgrades\"\n\nvar Transitions = upgrades.Transitions()\n", pkgName)), 0o644); err != nil {
			return fmt.Errorf("failed to create migrations package: %w", err)
		}
	}

	if err := dir.WriteFile(transition, []byte(fmt.Sprintf("package %s\n\nvar _ = Transitions.Simple(`SELECT 1 LIMIT ? -- replace this with a real transition`)", pkgName)), 0o644); err != nil {
		return fmt.Errorf("failed to create transition: %w", err)
	}

	if createGHES() {
		migration := fmt.Sprintf("%s_%s.up.sql", prefix, name)
		if err := dir.WriteFile(migration, []byte(fmt.Sprintf("-- this is a wrapper migration to run %q on GHES", transition)), 0o644); err != nil {
			return fmt.Errorf("failed to create migration: %w", err)
		}
		if err := updateNextTransition(dir); err != nil {
			return fmt.Errorf("failed to order migrations: %w", err)
		}
	}

	return nil
}

func confirm(prompt string) func() bool {
	return func() bool {
		fmt.Printf(prompt)
		var input string
		_, err := fmt.Scanf("%s", &input)
		if err != nil {
			return false
		}
		return strings.EqualFold(input, "y")
	}
}

func main() {
	log.SetFlags(0)

	var dest string
	flag.StringVar(&dest, "dest", "migrations", "destination directory for migrations")
	flag.Parse()
	if flag.NArg() != 1 || dest == "" {
		log.Fatal("usage: create-transition <transition name>")
	}

	pkgName := filepath.Base(dest)
	prefix := time.Now().Format("20060102150405")
	transition := flag.Arg(0)

	err := do(WriteDirFS(dest), pkgName, prefix, transition, confirm("Also create migration for GHES? (Y/N): "))
	if err != nil {
		log.Fatal(err)
	}
}
