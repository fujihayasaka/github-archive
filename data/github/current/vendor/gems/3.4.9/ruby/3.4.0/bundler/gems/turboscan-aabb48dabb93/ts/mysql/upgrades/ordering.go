package upgrades

import (
	"bufio"
	"bytes"
	"io/fs"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/errors"

	"golang.org/x/exp/slices"
)

type orderingItem struct {
	path    string
	version uint
}

func parseLatest(dir fs.FS) (uint, error) {
	data, err := fs.ReadFile(dir, "LATEST")
	if err != nil {
		return 0, err
	}

	s := bufio.NewScanner(bytes.NewReader(data))
	s.Split(bufio.ScanLines)

	for s.Scan() {
		if len(s.Text()) == 0 || strings.HasPrefix(s.Text(), "#") {
			continue
		}

		v, err := strconv.ParseUint(strings.TrimSpace(s.Text()), 10, 64)
		if err != nil {
			return 0, errors.Wrap(err, "could not parse LATEST file")
		}

		if v > math.MaxUint {
			return 0, errors.New("timestamp overflowed max uint")
		}

		currentTimestamp, err := strconv.ParseUint(time.Now().UTC().Format("20060102150405"), 10, 64)
		if err != nil {
			return 0, errors.Wrap(err, "could not parse current timestamp")
		}
		if v > currentTimestamp {
			return 0, errors.New("LATEST timestamp is in the future")
		}

		return uint(v), nil
	}

	return 0, errors.New("version number not found in LATEST")
}

// CheckOrdering will scan a directory of migrations to ensure that each one has a comment that points to the next
// migration.
// This allows us to catch any ordering issues and will create a merge conflict if two migrations are merged out of
// sequence.
func CheckOrdering(dir fs.FS) error {
	matches, err := fs.Glob(dir, "*.up.sql")
	if err != nil {
		return err
	}

	if len(matches) == 0 {
		return errors.Errorf("no migrations found at %v", dir)
	}

	latest, err := parseLatest(dir)
	if err != nil {
		return errors.Wrap(err, "please create a LATEST file that contains the latest migration timestamp")
	}

	var items []orderingItem
	for _, match := range matches {
		v, ok := VersionFromFile(match)
		if !ok {
			return errors.Errorf("could not extract version number from %s", match)
		}
		handle, err := dir.Open(match)
		if err != nil {
			return err
		}

		items = append(items, orderingItem{
			path:    match,
			version: v,
		})

		if err := handle.Close(); err != nil {
			return err
		}
	}

	slices.SortFunc(items, func(a, b orderingItem) int {
		if a.version != 0 && a.version < b.version {
			return -1
		} else if a.version > b.version {
			return 1
		}
		return 0
	})

	last := items[len(items)-1]

	if last.version != latest {
		return errors.Errorf(`LATEST should have version %d but has %d: please move your migration to the end of the migration chain and update LATEST`, latest, last.version)
	}

	return nil
}
