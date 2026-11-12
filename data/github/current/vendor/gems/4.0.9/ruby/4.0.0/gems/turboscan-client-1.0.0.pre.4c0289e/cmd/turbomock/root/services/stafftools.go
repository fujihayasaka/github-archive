package services

import (
	"context"

	"github.com/github/turboscan/ts/proto"
)

type StafftoolsResponses struct{}

func (s *StafftoolsResponses) DeleteAlerts(ctx context.Context, req *proto.DeleteAlertsRequest) (*proto.DeleteAlertsResponse, error) {
	return &proto.DeleteAlertsResponse{}, nil
}

func (s *StafftoolsResponses) GetTableAlertData(ctx context.Context, req *proto.GetTableAlertDataRequest) (*proto.GetTableAlertDataResponse, error) {
	return &proto.GetTableAlertDataResponse{}, nil
}
