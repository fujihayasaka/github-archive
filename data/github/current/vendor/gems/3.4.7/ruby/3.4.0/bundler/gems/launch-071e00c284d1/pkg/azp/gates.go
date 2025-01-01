package azp

import (
	"context"
)

type GatesClient interface {
	UpdateGateConclusion(ctx context.Context, gateID string, planID string, jobExternalID string, token string, isOpen bool) error
}

type GateConclusion struct {
	PlanID        string `json:"planId"` // `uuid` of `workflow_builds` / `external_id` from dotcom
	JobKey        string `json:"jobKey"` // e.g, build.ubuntu-latest
	JobExternalID string `json:"jobExternalId"`
	IsOpen        bool   `json:"isOpen"`
	State         string `json:"state"`
}
