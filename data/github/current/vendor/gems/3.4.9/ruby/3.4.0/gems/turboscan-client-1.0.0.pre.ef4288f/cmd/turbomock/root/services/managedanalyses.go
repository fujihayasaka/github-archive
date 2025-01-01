package services

import (
	"context"

	"github.com/github/turboscan/cmd/turbomock/data"
	"github.com/github/turboscan/ts/proto"
)

type ManagedAnalysisStatus uint8

const (
	ManagedAnalysisOff = iota
	ManagedAnalysisEnabling
	ManagedAnalysisEnabled
)

type ManagedAnalysesResponses struct {
	status             ManagedAnalysisStatus
	codeQualityEnabled bool
}

func (r *ManagedAnalysesResponses) GetManagedAnalysisInfo(ctx context.Context, _ *proto.GetManagedAnalysisInfoRequest) (resp *proto.GetManagedAnalysisInfoResponse, err error) {
	switch r.status {
	case ManagedAnalysisEnabling:
		r.status = ManagedAnalysisEnabled
		return data.LoadCassette(ctx, "get-managed-analysis-info-enabling.yml", resp)
	case ManagedAnalysisEnabled:
		resp, err = data.LoadCassette(ctx, "get-managed-analysis-info.yml", resp)
		resp.CodeQualityEnabled = r.codeQualityEnabled
		resp.CurrentConfig.CodeQualityEnabled = r.codeQualityEnabled
		return resp, err
	}
	return data.LoadCassette(ctx, "get-managed-analysis-info-disabled.yml", resp)
}

func (r *ManagedAnalysesResponses) Enable(ctx context.Context, _ *proto.EnableRequest) (resp *proto.EnableResponse, err error) {
	resp, err = data.LoadCassette(ctx, "managed-analyses-enable.yml", resp)
	r.status = ManagedAnalysisEnabled
	return
}

func (r *ManagedAnalysesResponses) Disable(ctx context.Context, _ *proto.DisableRequest) (resp *proto.DisableResponse, err error) {
	resp, err = data.LoadCassette(ctx, "managed-analyses-disable.yml", resp)
	r.status = ManagedAnalysisOff
	return
}

func (r *ManagedAnalysesResponses) Update(ctx context.Context, req *proto.UpdateRequest) (resp *proto.UpdateResponse, err error) {
	resp, err = data.LoadCassette(ctx, "managed-analyses-update.yml", resp)
	switch req.CodeQualityEnabled {
	case proto.UpdateRequest_CODE_QUALITY_ENABLED:
		r.codeQualityEnabled = true
	case proto.UpdateRequest_CODE_QUALITY_DISABLED:
		r.codeQualityEnabled = false
	case proto.UpdateRequest_CODE_QUALITY_UNCHANGED:
		// Do nothing, keep the current state.
	}
	return
}

func (r *ManagedAnalysesResponses) UpdateLanguages(ctx context.Context, _ *proto.UpdateLanguagesRequest) (resp *proto.UpdateLanguagesResponse, err error) {
	resp, err = data.LoadCassette(ctx, "managed-analyses-update-languages.yml", resp)
	return
}

func (r *ManagedAnalysesResponses) Adjust(ctx context.Context, _ *proto.AdjustRequest) (resp *proto.AdjustResponse, err error) {
	resp, err = data.LoadCassette(ctx, "managed-analyses-adjust.yml", resp)
	return
}

func (r *ManagedAnalysesResponses) SetRunConclusion(ctx context.Context, req *proto.SetRunConclusionRequest) (resp *proto.SetRunConclusionResponse, err error) {
	resp, err = data.LoadCassette(ctx, "managed-analyses-set-run-conclusion-completed.yml", resp)
	return
}
