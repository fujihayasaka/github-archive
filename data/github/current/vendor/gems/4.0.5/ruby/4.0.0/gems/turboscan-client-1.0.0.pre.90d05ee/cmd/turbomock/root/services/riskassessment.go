package services

import (
	"context"

	"github.com/github/turboscan/ts/proto"
)

type RiskAssessmentResponses struct{}

func (s *RiskAssessmentResponses) TriggerRiskAssessment(ctx context.Context, req *proto.TriggerRiskAssessmentRequest) (*proto.TriggerRiskAssessmentResponse, error) {
	return &proto.TriggerRiskAssessmentResponse{}, nil
}

func (s *RiskAssessmentResponses) ProcessRiskAssessment(ctx context.Context, req *proto.ProcessRiskAssessmentRequest) (*proto.ProcessRiskAssessmentResponse, error) {
	return &proto.ProcessRiskAssessmentResponse{}, nil
}
