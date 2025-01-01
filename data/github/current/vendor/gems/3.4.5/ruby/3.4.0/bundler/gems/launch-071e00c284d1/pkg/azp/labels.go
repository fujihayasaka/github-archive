package azp

import (
	"context"
)

type LabelsClient interface {
	ListLabels(ctx context.Context) ([]*Label, error)
	DeleteLabel(ctx context.Context, id int64) error
	CreateLabel(ctx context.Context, fields LabelFields) (*Label, error)
}

type Label struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	Type string `json:"type"`
}

type LabelFields struct {
	Name string `json:"name"`
	Type string `json:"type"`
}
