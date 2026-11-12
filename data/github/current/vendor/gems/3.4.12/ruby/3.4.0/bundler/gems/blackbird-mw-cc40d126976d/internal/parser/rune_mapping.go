package parser

// The rune mapping allows quick mapping between rune indices and byte indices
// within a string. This is used because we want byte indices in the parser,
// but the PEG library only provides rune indices.
type RuneMapping struct {
	// The offsets are the rune indices of extra bytes. By binary searching
	// within the offsets, the resulting position corresponds to the number
	// of extra bytes we must offset due to the extra unicode bytes.
	offsets   []uint32
	runeCount uint32
	byteCount uint32
}

func NewRuneMapping(s string) RuneMapping {
	out := []uint32{}
	runeIndex := uint32(0)
	offset := uint32(0)
	for byteIndex := range s {
		if runeIndex+offset != uint32(byteIndex) {
			for runeIndex+offset < uint32(byteIndex) {
				out = append(out, runeIndex)
				offset++
			}
		}
		runeIndex++
	}
	return RuneMapping{
		offsets:   out,
		runeCount: runeIndex,
		byteCount: uint32(len(s)),
	}
}

func (r RuneMapping) GetBytePos(runePos uint32) uint32 {
	if runePos >= r.runeCount {
		return r.byteCount
	}

	low := 0
	high := len(r.offsets) - 1

	for low <= high {
		mid := (low + high) / 2

		if r.offsets[mid] < runePos {
			low = mid + 1
		} else {
			high = mid - 1
		}
	}

	for low < len(r.offsets) && r.offsets[low] == runePos {
		low++
	}

	return uint32(low) + runePos
}
