package types

import (
	"fmt"

	"github.com/twitchtv/twirp"
)

const (
	dirMode = 0o040_000
	regMode = 0o100_644
	exeMode = 0o100_755
	symMode = 0o120_000
	subMode = 0o160_000
)

func NewMode(mode uint32) *Mode {
	return &Mode{Mode: mode}
}

func (m *Mode) Validate() error {
	if m == nil {
		return nil
	}

	if m.Mode == 0 {
		return twirp.RequiredArgumentError("mode.mode")
	}

	switch m.Mode {
	case dirMode, regMode, exeMode, symMode, subMode:
		break
	default:
		return twirp.InvalidArgumentError("mode.mode", "invalid mode")
	}

	return nil
}

func (m *Mode) IsDir() bool {
	return m.Mode == dirMode
}

func (m *Mode) IsRegular() bool {
	return m.Mode == regMode || m.Mode == exeMode
}

func (m *Mode) IsSymlink() bool {
	return m.Mode == symMode
}

func (m *Mode) IsSubmodule() bool {
	return m.Mode == subMode
}

func (m *Mode) ModeString() string {
	return fmt.Sprintf("%06o", m.Mode)
}
