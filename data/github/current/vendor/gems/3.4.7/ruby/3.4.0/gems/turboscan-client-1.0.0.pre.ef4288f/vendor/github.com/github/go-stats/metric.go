package stats

import "strconv"

// internal representation of a metric ready for delivery.
type metric struct {
	prefix   string
	name     string
	text     string
	value    float64
	rate     float32
	char     Type
	tags     tagBuffer
	conftags tagBuffer
}

func (m metric) serialize(buf []byte) []byte {
	if m.char == Event {
		return m.serializeAsEvent(buf)
	}
	if m.char == Set {
		return m.serializeAsSet(buf)
	}
	return m.serializeAsMetric(buf)
}

func (m metric) serializeAsMetric(buf []byte) []byte {
	buf = append(buf, m.prefix...)
	buf = append(buf, m.name...)
	buf = append(buf, ':')
	buf = strconv.AppendFloat(buf, m.value, 'g', 16, 64)
	buf = append(buf, []byte{'|', byte(m.char)}...)

	if m.rate < 1.0 {
		buf = append(buf, []byte{'|', '@'}...)
		buf = strconv.AppendFloat(buf, float64(m.rate), 'g', 4, 32)
	}

	return m.appendTags(buf)
}

func (m metric) serializeAsEvent(buf []byte) []byte {
	buf = append(buf, "_e{"...)
	buf = strconv.AppendInt(buf, int64(len(m.name)), 10)
	buf = append(buf, ',')
	buf = strconv.AppendInt(buf, int64(len(m.text)), 10)
	buf = append(buf, "}:"...)
	buf = append(buf, m.name...)
	buf = append(buf, '|')
	buf = append(buf, m.text...)

	return m.appendTags(buf)
}

func (m metric) serializeAsSet(buf []byte) []byte {
	buf = append(buf, m.prefix...)
	buf = append(buf, m.name...)
	buf = append(buf, ':')
	buf = append(buf, m.text...)
	buf = append(buf, []byte{'|', byte(m.char)}...)

	if m.rate < 1.0 {
		buf = append(buf, []byte{'|', '@'}...)
		buf = strconv.AppendFloat(buf, float64(m.rate), 'g', 4, 32)
	}

	return m.appendTags(buf)
}

func (m metric) appendTags(buf []byte) []byte {
	if len(m.conftags) != 0 || len(m.tags) != 0 {
		buf = append(buf, []byte{'|', '#'}...)
		buf = append(buf, m.conftags...)
		buf = append(buf, m.tags...)
		buf = buf[:len(buf)-1]
	}

	return append(buf, byte('\n'))
}
