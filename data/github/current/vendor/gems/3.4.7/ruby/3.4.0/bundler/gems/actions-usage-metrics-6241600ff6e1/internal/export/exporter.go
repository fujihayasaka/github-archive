package export

import (
	"encoding/csv"
	"fmt"
	"os"

	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type Exporter[T any] struct {
	items    []T
	headers  []*proto.ExportHeader
	provider ExportProvider[T]
}

type ExportProvider[T any] interface {
	GetFieldFromHeader(headerKey string, item T) (string, error)
}

func NewExporter[T any](headers []*proto.ExportHeader, items []T, provider ExportProvider[T]) *Exporter[T] {
	return &Exporter[T]{
		headers:  headers,
		items:    items,
		provider: provider,
	}
}

func (e *Exporter[T]) GetDisplayHeaders() []string {
	displayHeaders := make([]string, 0, len(e.headers))
	for _, header := range e.headers {
		if !utils.IsInternalColumn(header.Key) {
			displayHeaders = append(displayHeaders, utils.SanitizeString(header.GetDisplay(), false))
		}
	}
	return displayHeaders
}

func (e *Exporter[T]) ItemToCsv(item T) ([]string, error) {
	csvRowFields := make([]string, 0, len(e.headers))
	for _, header := range e.headers {
		if !utils.IsInternalColumn(header.Key) {
			fieldValue, err := e.provider.GetFieldFromHeader(header.GetKey(), item)
			if err != nil {
				return nil, err
			}
			csvRowFields = append(csvRowFields, utils.SanitizeString(fieldValue, common.IsNumericalColumnInCsv(header.GetKey())))
		}
	}
	return csvRowFields, nil
}

func (e *Exporter[T]) CreateCsvFile(blobName string) (*os.File, error) {
	// write to temp CSV file
	tmpFile, err := os.CreateTemp("", blobName)
	if err != nil {
		return nil, fmt.Errorf("failed to create temporary file: %w", err)
	}
	csvRecords, err := e.exportItems()
	if err != nil {
		return nil, fmt.Errorf("failed to export items: %w", err)
	}
	csvWriter := csv.NewWriter(tmpFile)
	err = csvWriter.WriteAll(csvRecords)
	if err != nil {
		return nil, fmt.Errorf("failed to write CSV records: %w", err)
	}

	return tmpFile, nil
}

func (e *Exporter[T]) exportItems() ([][]string, error) {
	records := make([][]string, 0, len(e.items))
	records = append(records, e.GetDisplayHeaders())
	for _, item := range e.items {
		row, err := e.ItemToCsv(item)
		if err != nil {
			return nil, fmt.Errorf("failed to convert item to CSV: %w", err)
		}
		records = append(records, row)
	}
	return records, nil
}
