// Package writer implements an exporter that writes data to a configured io.Writer.
package writer

import (
	"context"
	"io"
)

// Exporter defines a exporter that writes to a writer.
type Exporter struct {
	w io.Writer
}

// NewExporter returns a new Exporter that exports the given data by written to
// the given writer. One can use the following writers to emulate certain usages:
//
// file    : os.OpenFile()
// console : os.Stdout
// memory  : bytes.Buffer
//
//nolint:godot // comment shouldn't end in a period
func NewExporter(w io.Writer) *Exporter {
	return &Exporter{
		w: w,
	}
}

// Export exports the given data.
func (e *Exporter) Export(ctx context.Context, data []byte) error {
	_, err := e.w.Write(data)
	return err
}
