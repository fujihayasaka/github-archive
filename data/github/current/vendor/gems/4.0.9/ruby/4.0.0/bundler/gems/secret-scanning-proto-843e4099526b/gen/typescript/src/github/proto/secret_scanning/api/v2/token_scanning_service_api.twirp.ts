import {
  TwirpContext,
  TwirpServer,
  RouterEvents,
  TwirpError,
  TwirpErrorCode,
  Interceptor,
  TwirpContentType,
  chainInterceptors,
} from "twirp-ts";
import {
  GetTokensRequest,
  GetTokensResponse,
  GetTokenRequest,
  GetTokenResponse,
  GetTokenLocationsRequest,
  GetTokenLocationsResponse,
  GetTokensMeanTimeToRemediationRequest,
  GetTokensMeanTimeToRemediationResponse,
  ResolveTokenRequest,
  ResolveTokenResponse,
  ResolveTokensRequest,
  ResolveTokensResponse,
  GetTokenCountsRequest,
  GetTokenCountsResponse,
  GetTokenGroupByCountsRequest,
  GetTokenGroupByCountsResponse,
  GetTokenTypesInfoRequest,
  GetTokenTypesInfoResponse,
  ValidateEnabledReposRequest,
  ValidateEnabledReposResponse,
  AddTokenRemediationRequest,
  GetTokenLatestRemediationRequest,
  GetTokenLatestRemediationResponse,
  GetTimelineRequest,
  GetTimelineResponse,
  GetMoreTimelineEventsRequest,
  GetMoreTimelineEventsResponse,
  GetTokenValidationStatusRequest,
  GetTokenValidationStatusResponse,
  ReportTokenRequest,
  ReportTokenResponse,
  GetAdversarialAuditRequest,
  GetAdversarialAuditResponse,
  GetWorkflowAuditRequest,
  GetWorkflowAuditResponse,
  GetPermissionAuditRequest,
  GetPermissionAuditResponse,
  GetAutofixSuggestionRequest,
  GetAutofixSuggestionResponse,
  UpdateTokenWithClosureExemptionRequestIdRequest,
  SetAlertAssigneeRequest,
  SetAlertValidityRequest,
  CampaignAssignmentsRequest,
  CampaignAssignmentsResponse,
  GetTokenMetadataRequest,
  GetTokenMetadataResponse,
  CampaignDeletionRequest,
  CampaignDeletionResponse,
} from "./token_scanning_service_api";
import { Empty } from "../../google/protobuf/empty";

//==================================//
//          Client Code             //
//==================================//

interface Rpc {
  request(
    service: string,
    method: string,
    contentType: "application/json" | "application/protobuf",
    data: object | Uint8Array
  ): Promise<object | Uint8Array>;
}

export interface TokenAPIClient {
  GetTokens(request: GetTokensRequest): Promise<GetTokensResponse>;
  GetToken(request: GetTokenRequest): Promise<GetTokenResponse>;
  GetTokenLocations(
    request: GetTokenLocationsRequest
  ): Promise<GetTokenLocationsResponse>;
  GetTokensMeanTimeToRemediation(
    request: GetTokensMeanTimeToRemediationRequest
  ): Promise<GetTokensMeanTimeToRemediationResponse>;
  ResolveToken(request: ResolveTokenRequest): Promise<ResolveTokenResponse>;
  ResolveTokens(request: ResolveTokensRequest): Promise<ResolveTokensResponse>;
  GetTokenCounts(
    request: GetTokenCountsRequest
  ): Promise<GetTokenCountsResponse>;
  GetTokenGroupByCounts(
    request: GetTokenGroupByCountsRequest
  ): Promise<GetTokenGroupByCountsResponse>;
  GetTokenTypesInfo(
    request: GetTokenTypesInfoRequest
  ): Promise<GetTokenTypesInfoResponse>;
  ValidateEnabledRepos(
    request: ValidateEnabledReposRequest
  ): Promise<ValidateEnabledReposResponse>;
  AddTokenRemediation(request: AddTokenRemediationRequest): Promise<Empty>;
  GetTokenLatestRemediation(
    request: GetTokenLatestRemediationRequest
  ): Promise<GetTokenLatestRemediationResponse>;
  GetTimeline(request: GetTimelineRequest): Promise<GetTimelineResponse>;
  GetMoreTimelineEvents(
    request: GetMoreTimelineEventsRequest
  ): Promise<GetMoreTimelineEventsResponse>;
  GetTokenValidationStatus(
    request: GetTokenValidationStatusRequest
  ): Promise<GetTokenValidationStatusResponse>;
  ReportToken(request: ReportTokenRequest): Promise<ReportTokenResponse>;
  GetAdversarialAudit(
    request: GetAdversarialAuditRequest
  ): Promise<GetAdversarialAuditResponse>;
  GetWorkflowAudit(
    request: GetWorkflowAuditRequest
  ): Promise<GetWorkflowAuditResponse>;
  GetPermissionAudit(
    request: GetPermissionAuditRequest
  ): Promise<GetPermissionAuditResponse>;
  GetAutofixSuggestion(
    request: GetAutofixSuggestionRequest
  ): Promise<GetAutofixSuggestionResponse>;
  UpdateTokenWithClosureExemptionRequestId(
    request: UpdateTokenWithClosureExemptionRequestIdRequest
  ): Promise<Empty>;
  SetAlertAssignee(request: SetAlertAssigneeRequest): Promise<Empty>;
  SetAlertValidity(request: SetAlertValidityRequest): Promise<Empty>;
  SetCampaignAssignments(
    request: CampaignAssignmentsRequest
  ): Promise<CampaignAssignmentsResponse>;
  GetTokenMetadata(
    request: GetTokenMetadataRequest
  ): Promise<GetTokenMetadataResponse>;
  DeleteCampaign(
    request: CampaignDeletionRequest
  ): Promise<CampaignDeletionResponse>;
}

export class TokenAPIClientJSON implements TokenAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetTokens.bind(this);
    this.GetToken.bind(this);
    this.GetTokenLocations.bind(this);
    this.GetTokensMeanTimeToRemediation.bind(this);
    this.ResolveToken.bind(this);
    this.ResolveTokens.bind(this);
    this.GetTokenCounts.bind(this);
    this.GetTokenGroupByCounts.bind(this);
    this.GetTokenTypesInfo.bind(this);
    this.ValidateEnabledRepos.bind(this);
    this.AddTokenRemediation.bind(this);
    this.GetTokenLatestRemediation.bind(this);
    this.GetTimeline.bind(this);
    this.GetMoreTimelineEvents.bind(this);
    this.GetTokenValidationStatus.bind(this);
    this.ReportToken.bind(this);
    this.GetAdversarialAudit.bind(this);
    this.GetWorkflowAudit.bind(this);
    this.GetPermissionAudit.bind(this);
    this.GetAutofixSuggestion.bind(this);
    this.UpdateTokenWithClosureExemptionRequestId.bind(this);
    this.SetAlertAssignee.bind(this);
    this.SetAlertValidity.bind(this);
    this.SetCampaignAssignments.bind(this);
    this.GetTokenMetadata.bind(this);
    this.DeleteCampaign.bind(this);
  }
  GetTokens(request: GetTokensRequest): Promise<GetTokensResponse> {
    const data = GetTokensRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokens",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokensResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetToken(request: GetTokenRequest): Promise<GetTokenResponse> {
    const data = GetTokenRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetToken",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetTokenLocations(
    request: GetTokenLocationsRequest
  ): Promise<GetTokenLocationsResponse> {
    const data = GetTokenLocationsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenLocations",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenLocationsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokensMeanTimeToRemediation(
    request: GetTokensMeanTimeToRemediationRequest
  ): Promise<GetTokensMeanTimeToRemediationResponse> {
    const data = GetTokensMeanTimeToRemediationRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokensMeanTimeToRemediation",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokensMeanTimeToRemediationResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  ResolveToken(request: ResolveTokenRequest): Promise<ResolveTokenResponse> {
    const data = ResolveTokenRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ResolveToken",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ResolveTokenResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  ResolveTokens(request: ResolveTokensRequest): Promise<ResolveTokensResponse> {
    const data = ResolveTokensRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ResolveTokens",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ResolveTokensResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetTokenCounts(
    request: GetTokenCountsRequest
  ): Promise<GetTokenCountsResponse> {
    const data = GetTokenCountsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenCounts",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenCountsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenGroupByCounts(
    request: GetTokenGroupByCountsRequest
  ): Promise<GetTokenGroupByCountsResponse> {
    const data = GetTokenGroupByCountsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenGroupByCounts",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenGroupByCountsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenTypesInfo(
    request: GetTokenTypesInfoRequest
  ): Promise<GetTokenTypesInfoResponse> {
    const data = GetTokenTypesInfoRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenTypesInfo",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenTypesInfoResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  ValidateEnabledRepos(
    request: ValidateEnabledReposRequest
  ): Promise<ValidateEnabledReposResponse> {
    const data = ValidateEnabledReposRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ValidateEnabledRepos",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ValidateEnabledReposResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  AddTokenRemediation(request: AddTokenRemediationRequest): Promise<Empty> {
    const data = AddTokenRemediationRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "AddTokenRemediation",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetTokenLatestRemediation(
    request: GetTokenLatestRemediationRequest
  ): Promise<GetTokenLatestRemediationResponse> {
    const data = GetTokenLatestRemediationRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenLatestRemediation",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenLatestRemediationResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTimeline(request: GetTimelineRequest): Promise<GetTimelineResponse> {
    const data = GetTimelineRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTimeline",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTimelineResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetMoreTimelineEvents(
    request: GetMoreTimelineEventsRequest
  ): Promise<GetMoreTimelineEventsResponse> {
    const data = GetMoreTimelineEventsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetMoreTimelineEvents",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetMoreTimelineEventsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenValidationStatus(
    request: GetTokenValidationStatusRequest
  ): Promise<GetTokenValidationStatusResponse> {
    const data = GetTokenValidationStatusRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenValidationStatus",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenValidationStatusResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  ReportToken(request: ReportTokenRequest): Promise<ReportTokenResponse> {
    const data = ReportTokenRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ReportToken",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ReportTokenResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetAdversarialAudit(
    request: GetAdversarialAuditRequest
  ): Promise<GetAdversarialAuditResponse> {
    const data = GetAdversarialAuditRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetAdversarialAudit",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetAdversarialAuditResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetWorkflowAudit(
    request: GetWorkflowAuditRequest
  ): Promise<GetWorkflowAuditResponse> {
    const data = GetWorkflowAuditRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetWorkflowAudit",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetWorkflowAuditResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetPermissionAudit(
    request: GetPermissionAuditRequest
  ): Promise<GetPermissionAuditResponse> {
    const data = GetPermissionAuditRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetPermissionAudit",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetPermissionAuditResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetAutofixSuggestion(
    request: GetAutofixSuggestionRequest
  ): Promise<GetAutofixSuggestionResponse> {
    const data = GetAutofixSuggestionRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetAutofixSuggestion",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetAutofixSuggestionResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  UpdateTokenWithClosureExemptionRequestId(
    request: UpdateTokenWithClosureExemptionRequestIdRequest
  ): Promise<Empty> {
    const data = UpdateTokenWithClosureExemptionRequestIdRequest.toJson(
      request,
      { useProtoFieldName: true, emitDefaultValues: false }
    );
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "UpdateTokenWithClosureExemptionRequestId",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  SetAlertAssignee(request: SetAlertAssigneeRequest): Promise<Empty> {
    const data = SetAlertAssigneeRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "SetAlertAssignee",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  SetAlertValidity(request: SetAlertValidityRequest): Promise<Empty> {
    const data = SetAlertValidityRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "SetAlertValidity",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  SetCampaignAssignments(
    request: CampaignAssignmentsRequest
  ): Promise<CampaignAssignmentsResponse> {
    const data = CampaignAssignmentsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "SetCampaignAssignments",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      CampaignAssignmentsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenMetadata(
    request: GetTokenMetadataRequest
  ): Promise<GetTokenMetadataResponse> {
    const data = GetTokenMetadataRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenMetadata",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenMetadataResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  DeleteCampaign(
    request: CampaignDeletionRequest
  ): Promise<CampaignDeletionResponse> {
    const data = CampaignDeletionRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "DeleteCampaign",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      CampaignDeletionResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class TokenAPIClientProtobuf implements TokenAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetTokens.bind(this);
    this.GetToken.bind(this);
    this.GetTokenLocations.bind(this);
    this.GetTokensMeanTimeToRemediation.bind(this);
    this.ResolveToken.bind(this);
    this.ResolveTokens.bind(this);
    this.GetTokenCounts.bind(this);
    this.GetTokenGroupByCounts.bind(this);
    this.GetTokenTypesInfo.bind(this);
    this.ValidateEnabledRepos.bind(this);
    this.AddTokenRemediation.bind(this);
    this.GetTokenLatestRemediation.bind(this);
    this.GetTimeline.bind(this);
    this.GetMoreTimelineEvents.bind(this);
    this.GetTokenValidationStatus.bind(this);
    this.ReportToken.bind(this);
    this.GetAdversarialAudit.bind(this);
    this.GetWorkflowAudit.bind(this);
    this.GetPermissionAudit.bind(this);
    this.GetAutofixSuggestion.bind(this);
    this.UpdateTokenWithClosureExemptionRequestId.bind(this);
    this.SetAlertAssignee.bind(this);
    this.SetAlertValidity.bind(this);
    this.SetCampaignAssignments.bind(this);
    this.GetTokenMetadata.bind(this);
    this.DeleteCampaign.bind(this);
  }
  GetTokens(request: GetTokensRequest): Promise<GetTokensResponse> {
    const data = GetTokensRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokens",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokensResponse.fromBinary(data as Uint8Array)
    );
  }

  GetToken(request: GetTokenRequest): Promise<GetTokenResponse> {
    const data = GetTokenRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetToken",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenLocations(
    request: GetTokenLocationsRequest
  ): Promise<GetTokenLocationsResponse> {
    const data = GetTokenLocationsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenLocations",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenLocationsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokensMeanTimeToRemediation(
    request: GetTokensMeanTimeToRemediationRequest
  ): Promise<GetTokensMeanTimeToRemediationResponse> {
    const data = GetTokensMeanTimeToRemediationRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokensMeanTimeToRemediation",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokensMeanTimeToRemediationResponse.fromBinary(data as Uint8Array)
    );
  }

  ResolveToken(request: ResolveTokenRequest): Promise<ResolveTokenResponse> {
    const data = ResolveTokenRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ResolveToken",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ResolveTokenResponse.fromBinary(data as Uint8Array)
    );
  }

  ResolveTokens(request: ResolveTokensRequest): Promise<ResolveTokensResponse> {
    const data = ResolveTokensRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ResolveTokens",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ResolveTokensResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenCounts(
    request: GetTokenCountsRequest
  ): Promise<GetTokenCountsResponse> {
    const data = GetTokenCountsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenCounts",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenCountsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenGroupByCounts(
    request: GetTokenGroupByCountsRequest
  ): Promise<GetTokenGroupByCountsResponse> {
    const data = GetTokenGroupByCountsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenGroupByCounts",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenGroupByCountsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenTypesInfo(
    request: GetTokenTypesInfoRequest
  ): Promise<GetTokenTypesInfoResponse> {
    const data = GetTokenTypesInfoRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenTypesInfo",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenTypesInfoResponse.fromBinary(data as Uint8Array)
    );
  }

  ValidateEnabledRepos(
    request: ValidateEnabledReposRequest
  ): Promise<ValidateEnabledReposResponse> {
    const data = ValidateEnabledReposRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ValidateEnabledRepos",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ValidateEnabledReposResponse.fromBinary(data as Uint8Array)
    );
  }

  AddTokenRemediation(request: AddTokenRemediationRequest): Promise<Empty> {
    const data = AddTokenRemediationRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "AddTokenRemediation",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  GetTokenLatestRemediation(
    request: GetTokenLatestRemediationRequest
  ): Promise<GetTokenLatestRemediationResponse> {
    const data = GetTokenLatestRemediationRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenLatestRemediation",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenLatestRemediationResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTimeline(request: GetTimelineRequest): Promise<GetTimelineResponse> {
    const data = GetTimelineRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTimeline",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTimelineResponse.fromBinary(data as Uint8Array)
    );
  }

  GetMoreTimelineEvents(
    request: GetMoreTimelineEventsRequest
  ): Promise<GetMoreTimelineEventsResponse> {
    const data = GetMoreTimelineEventsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetMoreTimelineEvents",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetMoreTimelineEventsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenValidationStatus(
    request: GetTokenValidationStatusRequest
  ): Promise<GetTokenValidationStatusResponse> {
    const data = GetTokenValidationStatusRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenValidationStatus",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenValidationStatusResponse.fromBinary(data as Uint8Array)
    );
  }

  ReportToken(request: ReportTokenRequest): Promise<ReportTokenResponse> {
    const data = ReportTokenRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "ReportToken",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ReportTokenResponse.fromBinary(data as Uint8Array)
    );
  }

  GetAdversarialAudit(
    request: GetAdversarialAuditRequest
  ): Promise<GetAdversarialAuditResponse> {
    const data = GetAdversarialAuditRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetAdversarialAudit",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetAdversarialAuditResponse.fromBinary(data as Uint8Array)
    );
  }

  GetWorkflowAudit(
    request: GetWorkflowAuditRequest
  ): Promise<GetWorkflowAuditResponse> {
    const data = GetWorkflowAuditRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetWorkflowAudit",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetWorkflowAuditResponse.fromBinary(data as Uint8Array)
    );
  }

  GetPermissionAudit(
    request: GetPermissionAuditRequest
  ): Promise<GetPermissionAuditResponse> {
    const data = GetPermissionAuditRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetPermissionAudit",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetPermissionAuditResponse.fromBinary(data as Uint8Array)
    );
  }

  GetAutofixSuggestion(
    request: GetAutofixSuggestionRequest
  ): Promise<GetAutofixSuggestionResponse> {
    const data = GetAutofixSuggestionRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetAutofixSuggestion",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetAutofixSuggestionResponse.fromBinary(data as Uint8Array)
    );
  }

  UpdateTokenWithClosureExemptionRequestId(
    request: UpdateTokenWithClosureExemptionRequestIdRequest
  ): Promise<Empty> {
    const data =
      UpdateTokenWithClosureExemptionRequestIdRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "UpdateTokenWithClosureExemptionRequestId",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  SetAlertAssignee(request: SetAlertAssigneeRequest): Promise<Empty> {
    const data = SetAlertAssigneeRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "SetAlertAssignee",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  SetAlertValidity(request: SetAlertValidityRequest): Promise<Empty> {
    const data = SetAlertValidityRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "SetAlertValidity",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  SetCampaignAssignments(
    request: CampaignAssignmentsRequest
  ): Promise<CampaignAssignmentsResponse> {
    const data = CampaignAssignmentsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "SetCampaignAssignments",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      CampaignAssignmentsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenMetadata(
    request: GetTokenMetadataRequest
  ): Promise<GetTokenMetadataResponse> {
    const data = GetTokenMetadataRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "GetTokenMetadata",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenMetadataResponse.fromBinary(data as Uint8Array)
    );
  }

  DeleteCampaign(
    request: CampaignDeletionRequest
  ): Promise<CampaignDeletionResponse> {
    const data = CampaignDeletionRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.TokenAPI",
      "DeleteCampaign",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      CampaignDeletionResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface TokenAPITwirp<T extends TwirpContext = TwirpContext> {
  GetTokens(ctx: T, request: GetTokensRequest): Promise<GetTokensResponse>;
  GetToken(ctx: T, request: GetTokenRequest): Promise<GetTokenResponse>;
  GetTokenLocations(
    ctx: T,
    request: GetTokenLocationsRequest
  ): Promise<GetTokenLocationsResponse>;
  GetTokensMeanTimeToRemediation(
    ctx: T,
    request: GetTokensMeanTimeToRemediationRequest
  ): Promise<GetTokensMeanTimeToRemediationResponse>;
  ResolveToken(
    ctx: T,
    request: ResolveTokenRequest
  ): Promise<ResolveTokenResponse>;
  ResolveTokens(
    ctx: T,
    request: ResolveTokensRequest
  ): Promise<ResolveTokensResponse>;
  GetTokenCounts(
    ctx: T,
    request: GetTokenCountsRequest
  ): Promise<GetTokenCountsResponse>;
  GetTokenGroupByCounts(
    ctx: T,
    request: GetTokenGroupByCountsRequest
  ): Promise<GetTokenGroupByCountsResponse>;
  GetTokenTypesInfo(
    ctx: T,
    request: GetTokenTypesInfoRequest
  ): Promise<GetTokenTypesInfoResponse>;
  ValidateEnabledRepos(
    ctx: T,
    request: ValidateEnabledReposRequest
  ): Promise<ValidateEnabledReposResponse>;
  AddTokenRemediation(
    ctx: T,
    request: AddTokenRemediationRequest
  ): Promise<Empty>;
  GetTokenLatestRemediation(
    ctx: T,
    request: GetTokenLatestRemediationRequest
  ): Promise<GetTokenLatestRemediationResponse>;
  GetTimeline(
    ctx: T,
    request: GetTimelineRequest
  ): Promise<GetTimelineResponse>;
  GetMoreTimelineEvents(
    ctx: T,
    request: GetMoreTimelineEventsRequest
  ): Promise<GetMoreTimelineEventsResponse>;
  GetTokenValidationStatus(
    ctx: T,
    request: GetTokenValidationStatusRequest
  ): Promise<GetTokenValidationStatusResponse>;
  ReportToken(
    ctx: T,
    request: ReportTokenRequest
  ): Promise<ReportTokenResponse>;
  GetAdversarialAudit(
    ctx: T,
    request: GetAdversarialAuditRequest
  ): Promise<GetAdversarialAuditResponse>;
  GetWorkflowAudit(
    ctx: T,
    request: GetWorkflowAuditRequest
  ): Promise<GetWorkflowAuditResponse>;
  GetPermissionAudit(
    ctx: T,
    request: GetPermissionAuditRequest
  ): Promise<GetPermissionAuditResponse>;
  GetAutofixSuggestion(
    ctx: T,
    request: GetAutofixSuggestionRequest
  ): Promise<GetAutofixSuggestionResponse>;
  UpdateTokenWithClosureExemptionRequestId(
    ctx: T,
    request: UpdateTokenWithClosureExemptionRequestIdRequest
  ): Promise<Empty>;
  SetAlertAssignee(ctx: T, request: SetAlertAssigneeRequest): Promise<Empty>;
  SetAlertValidity(ctx: T, request: SetAlertValidityRequest): Promise<Empty>;
  SetCampaignAssignments(
    ctx: T,
    request: CampaignAssignmentsRequest
  ): Promise<CampaignAssignmentsResponse>;
  GetTokenMetadata(
    ctx: T,
    request: GetTokenMetadataRequest
  ): Promise<GetTokenMetadataResponse>;
  DeleteCampaign(
    ctx: T,
    request: CampaignDeletionRequest
  ): Promise<CampaignDeletionResponse>;
}

export enum TokenAPIMethod {
  GetTokens = "GetTokens",
  GetToken = "GetToken",
  GetTokenLocations = "GetTokenLocations",
  GetTokensMeanTimeToRemediation = "GetTokensMeanTimeToRemediation",
  ResolveToken = "ResolveToken",
  ResolveTokens = "ResolveTokens",
  GetTokenCounts = "GetTokenCounts",
  GetTokenGroupByCounts = "GetTokenGroupByCounts",
  GetTokenTypesInfo = "GetTokenTypesInfo",
  ValidateEnabledRepos = "ValidateEnabledRepos",
  AddTokenRemediation = "AddTokenRemediation",
  GetTokenLatestRemediation = "GetTokenLatestRemediation",
  GetTimeline = "GetTimeline",
  GetMoreTimelineEvents = "GetMoreTimelineEvents",
  GetTokenValidationStatus = "GetTokenValidationStatus",
  ReportToken = "ReportToken",
  GetAdversarialAudit = "GetAdversarialAudit",
  GetWorkflowAudit = "GetWorkflowAudit",
  GetPermissionAudit = "GetPermissionAudit",
  GetAutofixSuggestion = "GetAutofixSuggestion",
  UpdateTokenWithClosureExemptionRequestId = "UpdateTokenWithClosureExemptionRequestId",
  SetAlertAssignee = "SetAlertAssignee",
  SetAlertValidity = "SetAlertValidity",
  SetCampaignAssignments = "SetCampaignAssignments",
  GetTokenMetadata = "GetTokenMetadata",
  DeleteCampaign = "DeleteCampaign",
}

export const TokenAPIMethodList = [
  TokenAPIMethod.GetTokens,
  TokenAPIMethod.GetToken,
  TokenAPIMethod.GetTokenLocations,
  TokenAPIMethod.GetTokensMeanTimeToRemediation,
  TokenAPIMethod.ResolveToken,
  TokenAPIMethod.ResolveTokens,
  TokenAPIMethod.GetTokenCounts,
  TokenAPIMethod.GetTokenGroupByCounts,
  TokenAPIMethod.GetTokenTypesInfo,
  TokenAPIMethod.ValidateEnabledRepos,
  TokenAPIMethod.AddTokenRemediation,
  TokenAPIMethod.GetTokenLatestRemediation,
  TokenAPIMethod.GetTimeline,
  TokenAPIMethod.GetMoreTimelineEvents,
  TokenAPIMethod.GetTokenValidationStatus,
  TokenAPIMethod.ReportToken,
  TokenAPIMethod.GetAdversarialAudit,
  TokenAPIMethod.GetWorkflowAudit,
  TokenAPIMethod.GetPermissionAudit,
  TokenAPIMethod.GetAutofixSuggestion,
  TokenAPIMethod.UpdateTokenWithClosureExemptionRequestId,
  TokenAPIMethod.SetAlertAssignee,
  TokenAPIMethod.SetAlertValidity,
  TokenAPIMethod.SetCampaignAssignments,
  TokenAPIMethod.GetTokenMetadata,
  TokenAPIMethod.DeleteCampaign,
];

export function createTokenAPIServer<T extends TwirpContext = TwirpContext>(
  service: TokenAPITwirp<T>
) {
  return new TwirpServer<TokenAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v2",
    serviceName: "TokenAPI",
    methodList: TokenAPIMethodList,
    matchRoute: matchTokenAPIRoute,
  });
}

function matchTokenAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetTokens":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, GetTokensRequest, GetTokensResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokens" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokensRequest(ctx, service, data, interceptors);
      };
    case "GetToken":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, GetTokenRequest, GetTokenResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "GetToken" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenRequest(ctx, service, data, interceptors);
      };
    case "GetTokenLocations":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenLocationsRequest,
          GetTokenLocationsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenLocations" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenLocationsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokensMeanTimeToRemediation":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokensMeanTimeToRemediationRequest,
          GetTokensMeanTimeToRemediationResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokensMeanTimeToRemediation" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokensMeanTimeToRemediationRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ResolveToken":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ResolveTokenRequest,
          ResolveTokenResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ResolveToken" };
        await events.onMatch(ctx);
        return handleTokenAPIResolveTokenRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ResolveTokens":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ResolveTokensRequest,
          ResolveTokensResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ResolveTokens" };
        await events.onMatch(ctx);
        return handleTokenAPIResolveTokensRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenCounts":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenCountsRequest,
          GetTokenCountsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenCounts" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenCountsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenGroupByCounts":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenGroupByCountsRequest,
          GetTokenGroupByCountsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenGroupByCounts" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenGroupByCountsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenTypesInfo":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenTypesInfoRequest,
          GetTokenTypesInfoResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenTypesInfo" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenTypesInfoRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ValidateEnabledRepos":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ValidateEnabledReposRequest,
          ValidateEnabledReposResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ValidateEnabledRepos" };
        await events.onMatch(ctx);
        return handleTokenAPIValidateEnabledReposRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "AddTokenRemediation":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, AddTokenRemediationRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "AddTokenRemediation" };
        await events.onMatch(ctx);
        return handleTokenAPIAddTokenRemediationRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenLatestRemediation":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenLatestRemediationRequest,
          GetTokenLatestRemediationResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenLatestRemediation" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenLatestRemediationRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTimeline":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, GetTimelineRequest, GetTimelineResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "GetTimeline" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTimelineRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetMoreTimelineEvents":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetMoreTimelineEventsRequest,
          GetMoreTimelineEventsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetMoreTimelineEvents" };
        await events.onMatch(ctx);
        return handleTokenAPIGetMoreTimelineEventsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenValidationStatus":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenValidationStatusRequest,
          GetTokenValidationStatusResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenValidationStatus" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenValidationStatusRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ReportToken":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, ReportTokenRequest, ReportTokenResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "ReportToken" };
        await events.onMatch(ctx);
        return handleTokenAPIReportTokenRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetAdversarialAudit":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetAdversarialAuditRequest,
          GetAdversarialAuditResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetAdversarialAudit" };
        await events.onMatch(ctx);
        return handleTokenAPIGetAdversarialAuditRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetWorkflowAudit":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetWorkflowAuditRequest,
          GetWorkflowAuditResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetWorkflowAudit" };
        await events.onMatch(ctx);
        return handleTokenAPIGetWorkflowAuditRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetPermissionAudit":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetPermissionAuditRequest,
          GetPermissionAuditResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetPermissionAudit" };
        await events.onMatch(ctx);
        return handleTokenAPIGetPermissionAuditRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetAutofixSuggestion":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetAutofixSuggestionRequest,
          GetAutofixSuggestionResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetAutofixSuggestion" };
        await events.onMatch(ctx);
        return handleTokenAPIGetAutofixSuggestionRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "UpdateTokenWithClosureExemptionRequestId":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          UpdateTokenWithClosureExemptionRequestIdRequest,
          Empty
        >[]
      ) => {
        ctx = {
          ...ctx,
          methodName: "UpdateTokenWithClosureExemptionRequestId",
        };
        await events.onMatch(ctx);
        return handleTokenAPIUpdateTokenWithClosureExemptionRequestIdRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "SetAlertAssignee":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, SetAlertAssigneeRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "SetAlertAssignee" };
        await events.onMatch(ctx);
        return handleTokenAPISetAlertAssigneeRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "SetAlertValidity":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, SetAlertValidityRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "SetAlertValidity" };
        await events.onMatch(ctx);
        return handleTokenAPISetAlertValidityRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "SetCampaignAssignments":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          CampaignAssignmentsRequest,
          CampaignAssignmentsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "SetCampaignAssignments" };
        await events.onMatch(ctx);
        return handleTokenAPISetCampaignAssignmentsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenMetadata":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenMetadataRequest,
          GetTokenMetadataResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenMetadata" };
        await events.onMatch(ctx);
        return handleTokenAPIGetTokenMetadataRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "DeleteCampaign":
      return async (
        ctx: T,
        service: TokenAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          CampaignDeletionRequest,
          CampaignDeletionResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "DeleteCampaign" };
        await events.onMatch(ctx);
        return handleTokenAPIDeleteCampaignRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    default:
      events.onNotFound();
      const msg = `no handler found`;
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokensRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokensRequest, GetTokensResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokensJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokensProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokenRequest, GetTokenResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenLocationsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenLocationsRequest,
    GetTokenLocationsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenLocationsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenLocationsProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokensMeanTimeToRemediationRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokensMeanTimeToRemediationRequest,
    GetTokensMeanTimeToRemediationResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokensMeanTimeToRemediationJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokensMeanTimeToRemediationProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIResolveTokenRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ResolveTokenRequest, ResolveTokenResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIResolveTokenJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIResolveTokenProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIResolveTokensRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ResolveTokensRequest, ResolveTokensResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIResolveTokensJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIResolveTokensProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenCountsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokenCountsRequest, GetTokenCountsResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenCountsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenCountsProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenGroupByCountsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenGroupByCountsRequest,
    GetTokenGroupByCountsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenGroupByCountsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenGroupByCountsProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenTypesInfoRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypesInfoRequest,
    GetTokenTypesInfoResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenTypesInfoJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenTypesInfoProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIValidateEnabledReposRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ValidateEnabledReposRequest,
    ValidateEnabledReposResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIValidateEnabledReposJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIValidateEnabledReposProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIAddTokenRemediationRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddTokenRemediationRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIAddTokenRemediationJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIAddTokenRemediationProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenLatestRemediationRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenLatestRemediationRequest,
    GetTokenLatestRemediationResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenLatestRemediationJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenLatestRemediationProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTimelineRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTimelineRequest, GetTimelineResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTimelineJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTimelineProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetMoreTimelineEventsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetMoreTimelineEventsRequest,
    GetMoreTimelineEventsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetMoreTimelineEventsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetMoreTimelineEventsProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenValidationStatusRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenValidationStatusRequest,
    GetTokenValidationStatusResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenValidationStatusJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenValidationStatusProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIReportTokenRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ReportTokenRequest, ReportTokenResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIReportTokenJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleTokenAPIReportTokenProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetAdversarialAuditRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAdversarialAuditRequest,
    GetAdversarialAuditResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetAdversarialAuditJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetAdversarialAuditProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetWorkflowAuditRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetWorkflowAuditRequest,
    GetWorkflowAuditResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetWorkflowAuditJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetWorkflowAuditProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetPermissionAuditRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPermissionAuditRequest,
    GetPermissionAuditResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetPermissionAuditJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetPermissionAuditProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetAutofixSuggestionRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAutofixSuggestionRequest,
    GetAutofixSuggestionResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetAutofixSuggestionJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetAutofixSuggestionProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIUpdateTokenWithClosureExemptionRequestIdRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateTokenWithClosureExemptionRequestIdRequest,
    Empty
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIUpdateTokenWithClosureExemptionRequestIdJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIUpdateTokenWithClosureExemptionRequestIdProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPISetAlertAssigneeRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, SetAlertAssigneeRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPISetAlertAssigneeJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPISetAlertAssigneeProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPISetAlertValidityRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, SetAlertValidityRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPISetAlertValidityJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPISetAlertValidityProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPISetCampaignAssignmentsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CampaignAssignmentsRequest,
    CampaignAssignmentsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPISetCampaignAssignmentsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPISetCampaignAssignmentsProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIGetTokenMetadataRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenMetadataRequest,
    GetTokenMetadataResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIGetTokenMetadataJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIGetTokenMetadataProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleTokenAPIDeleteCampaignRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CampaignDeletionRequest,
    CampaignDeletionResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTokenAPIDeleteCampaignJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleTokenAPIDeleteCampaignProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}
async function handleTokenAPIGetTokensJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokensRequest, GetTokensResponse>[]
) {
  let request: GetTokensRequest;
  let response: GetTokensResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokensRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokensRequest,
      GetTokensResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokens(ctx, inputReq);
    });
  } else {
    response = await service.GetTokens(ctx, request!);
  }

  return JSON.stringify(
    GetTokensResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokenRequest, GetTokenResponse>[]
) {
  let request: GetTokenRequest;
  let response: GetTokenResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenRequest,
      GetTokenResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetToken(ctx, inputReq);
    });
  } else {
    response = await service.GetToken(ctx, request!);
  }

  return JSON.stringify(
    GetTokenResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenLocationsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenLocationsRequest,
    GetTokenLocationsResponse
  >[]
) {
  let request: GetTokenLocationsRequest;
  let response: GetTokenLocationsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenLocationsRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenLocationsRequest,
      GetTokenLocationsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenLocations(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenLocations(ctx, request!);
  }

  return JSON.stringify(
    GetTokenLocationsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokensMeanTimeToRemediationJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokensMeanTimeToRemediationRequest,
    GetTokensMeanTimeToRemediationResponse
  >[]
) {
  let request: GetTokensMeanTimeToRemediationRequest;
  let response: GetTokensMeanTimeToRemediationResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokensMeanTimeToRemediationRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokensMeanTimeToRemediationRequest,
      GetTokensMeanTimeToRemediationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokensMeanTimeToRemediation(ctx, inputReq);
    });
  } else {
    response = await service.GetTokensMeanTimeToRemediation(ctx, request!);
  }

  return JSON.stringify(
    GetTokensMeanTimeToRemediationResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIResolveTokenJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ResolveTokenRequest, ResolveTokenResponse>[]
) {
  let request: ResolveTokenRequest;
  let response: ResolveTokenResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ResolveTokenRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ResolveTokenRequest,
      ResolveTokenResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ResolveToken(ctx, inputReq);
    });
  } else {
    response = await service.ResolveToken(ctx, request!);
  }

  return JSON.stringify(
    ResolveTokenResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIResolveTokensJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ResolveTokensRequest, ResolveTokensResponse>[]
) {
  let request: ResolveTokensRequest;
  let response: ResolveTokensResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ResolveTokensRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ResolveTokensRequest,
      ResolveTokensResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ResolveTokens(ctx, inputReq);
    });
  } else {
    response = await service.ResolveTokens(ctx, request!);
  }

  return JSON.stringify(
    ResolveTokensResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenCountsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokenCountsRequest, GetTokenCountsResponse>[]
) {
  let request: GetTokenCountsRequest;
  let response: GetTokenCountsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenCountsRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenCountsRequest,
      GetTokenCountsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenCounts(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenCounts(ctx, request!);
  }

  return JSON.stringify(
    GetTokenCountsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenGroupByCountsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenGroupByCountsRequest,
    GetTokenGroupByCountsResponse
  >[]
) {
  let request: GetTokenGroupByCountsRequest;
  let response: GetTokenGroupByCountsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenGroupByCountsRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenGroupByCountsRequest,
      GetTokenGroupByCountsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenGroupByCounts(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenGroupByCounts(ctx, request!);
  }

  return JSON.stringify(
    GetTokenGroupByCountsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenTypesInfoJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypesInfoRequest,
    GetTokenTypesInfoResponse
  >[]
) {
  let request: GetTokenTypesInfoRequest;
  let response: GetTokenTypesInfoResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenTypesInfoRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenTypesInfoRequest,
      GetTokenTypesInfoResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenTypesInfo(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenTypesInfo(ctx, request!);
  }

  return JSON.stringify(
    GetTokenTypesInfoResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIValidateEnabledReposJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ValidateEnabledReposRequest,
    ValidateEnabledReposResponse
  >[]
) {
  let request: ValidateEnabledReposRequest;
  let response: ValidateEnabledReposResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ValidateEnabledReposRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ValidateEnabledReposRequest,
      ValidateEnabledReposResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ValidateEnabledRepos(ctx, inputReq);
    });
  } else {
    response = await service.ValidateEnabledRepos(ctx, request!);
  }

  return JSON.stringify(
    ValidateEnabledReposResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIAddTokenRemediationJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddTokenRemediationRequest, Empty>[]
) {
  let request: AddTokenRemediationRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = AddTokenRemediationRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      AddTokenRemediationRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddTokenRemediation(ctx, inputReq);
    });
  } else {
    response = await service.AddTokenRemediation(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenLatestRemediationJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenLatestRemediationRequest,
    GetTokenLatestRemediationResponse
  >[]
) {
  let request: GetTokenLatestRemediationRequest;
  let response: GetTokenLatestRemediationResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenLatestRemediationRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenLatestRemediationRequest,
      GetTokenLatestRemediationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenLatestRemediation(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenLatestRemediation(ctx, request!);
  }

  return JSON.stringify(
    GetTokenLatestRemediationResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTimelineJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTimelineRequest, GetTimelineResponse>[]
) {
  let request: GetTimelineRequest;
  let response: GetTimelineResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTimelineRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTimelineRequest,
      GetTimelineResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTimeline(ctx, inputReq);
    });
  } else {
    response = await service.GetTimeline(ctx, request!);
  }

  return JSON.stringify(
    GetTimelineResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetMoreTimelineEventsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetMoreTimelineEventsRequest,
    GetMoreTimelineEventsResponse
  >[]
) {
  let request: GetMoreTimelineEventsRequest;
  let response: GetMoreTimelineEventsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetMoreTimelineEventsRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetMoreTimelineEventsRequest,
      GetMoreTimelineEventsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetMoreTimelineEvents(ctx, inputReq);
    });
  } else {
    response = await service.GetMoreTimelineEvents(ctx, request!);
  }

  return JSON.stringify(
    GetMoreTimelineEventsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenValidationStatusJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenValidationStatusRequest,
    GetTokenValidationStatusResponse
  >[]
) {
  let request: GetTokenValidationStatusRequest;
  let response: GetTokenValidationStatusResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenValidationStatusRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenValidationStatusRequest,
      GetTokenValidationStatusResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenValidationStatus(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenValidationStatus(ctx, request!);
  }

  return JSON.stringify(
    GetTokenValidationStatusResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIReportTokenJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ReportTokenRequest, ReportTokenResponse>[]
) {
  let request: ReportTokenRequest;
  let response: ReportTokenResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ReportTokenRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ReportTokenRequest,
      ReportTokenResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ReportToken(ctx, inputReq);
    });
  } else {
    response = await service.ReportToken(ctx, request!);
  }

  return JSON.stringify(
    ReportTokenResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetAdversarialAuditJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAdversarialAuditRequest,
    GetAdversarialAuditResponse
  >[]
) {
  let request: GetAdversarialAuditRequest;
  let response: GetAdversarialAuditResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetAdversarialAuditRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetAdversarialAuditRequest,
      GetAdversarialAuditResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAdversarialAudit(ctx, inputReq);
    });
  } else {
    response = await service.GetAdversarialAudit(ctx, request!);
  }

  return JSON.stringify(
    GetAdversarialAuditResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetWorkflowAuditJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetWorkflowAuditRequest,
    GetWorkflowAuditResponse
  >[]
) {
  let request: GetWorkflowAuditRequest;
  let response: GetWorkflowAuditResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetWorkflowAuditRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetWorkflowAuditRequest,
      GetWorkflowAuditResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetWorkflowAudit(ctx, inputReq);
    });
  } else {
    response = await service.GetWorkflowAudit(ctx, request!);
  }

  return JSON.stringify(
    GetWorkflowAuditResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetPermissionAuditJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPermissionAuditRequest,
    GetPermissionAuditResponse
  >[]
) {
  let request: GetPermissionAuditRequest;
  let response: GetPermissionAuditResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetPermissionAuditRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetPermissionAuditRequest,
      GetPermissionAuditResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPermissionAudit(ctx, inputReq);
    });
  } else {
    response = await service.GetPermissionAudit(ctx, request!);
  }

  return JSON.stringify(
    GetPermissionAuditResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetAutofixSuggestionJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAutofixSuggestionRequest,
    GetAutofixSuggestionResponse
  >[]
) {
  let request: GetAutofixSuggestionRequest;
  let response: GetAutofixSuggestionResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetAutofixSuggestionRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetAutofixSuggestionRequest,
      GetAutofixSuggestionResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAutofixSuggestion(ctx, inputReq);
    });
  } else {
    response = await service.GetAutofixSuggestion(ctx, request!);
  }

  return JSON.stringify(
    GetAutofixSuggestionResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIUpdateTokenWithClosureExemptionRequestIdJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateTokenWithClosureExemptionRequestIdRequest,
    Empty
  >[]
) {
  let request: UpdateTokenWithClosureExemptionRequestIdRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = UpdateTokenWithClosureExemptionRequestIdRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UpdateTokenWithClosureExemptionRequestIdRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateTokenWithClosureExemptionRequestId(ctx, inputReq);
    });
  } else {
    response = await service.UpdateTokenWithClosureExemptionRequestId(
      ctx,
      request!
    );
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPISetAlertAssigneeJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, SetAlertAssigneeRequest, Empty>[]
) {
  let request: SetAlertAssigneeRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = SetAlertAssigneeRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      SetAlertAssigneeRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.SetAlertAssignee(ctx, inputReq);
    });
  } else {
    response = await service.SetAlertAssignee(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPISetAlertValidityJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, SetAlertValidityRequest, Empty>[]
) {
  let request: SetAlertValidityRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = SetAlertValidityRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      SetAlertValidityRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.SetAlertValidity(ctx, inputReq);
    });
  } else {
    response = await service.SetAlertValidity(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPISetCampaignAssignmentsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CampaignAssignmentsRequest,
    CampaignAssignmentsResponse
  >[]
) {
  let request: CampaignAssignmentsRequest;
  let response: CampaignAssignmentsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = CampaignAssignmentsRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CampaignAssignmentsRequest,
      CampaignAssignmentsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.SetCampaignAssignments(ctx, inputReq);
    });
  } else {
    response = await service.SetCampaignAssignments(ctx, request!);
  }

  return JSON.stringify(
    CampaignAssignmentsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIGetTokenMetadataJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenMetadataRequest,
    GetTokenMetadataResponse
  >[]
) {
  let request: GetTokenMetadataRequest;
  let response: GetTokenMetadataResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenMetadataRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenMetadataRequest,
      GetTokenMetadataResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenMetadata(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenMetadata(ctx, request!);
  }

  return JSON.stringify(
    GetTokenMetadataResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleTokenAPIDeleteCampaignJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CampaignDeletionRequest,
    CampaignDeletionResponse
  >[]
) {
  let request: CampaignDeletionRequest;
  let response: CampaignDeletionResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = CampaignDeletionRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CampaignDeletionRequest,
      CampaignDeletionResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DeleteCampaign(ctx, inputReq);
    });
  } else {
    response = await service.DeleteCampaign(ctx, request!);
  }

  return JSON.stringify(
    CampaignDeletionResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleTokenAPIGetTokensProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokensRequest, GetTokensResponse>[]
) {
  let request: GetTokensRequest;
  let response: GetTokensResponse;

  try {
    request = GetTokensRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokensRequest,
      GetTokensResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokens(ctx, inputReq);
    });
  } else {
    response = await service.GetTokens(ctx, request!);
  }

  return Buffer.from(GetTokensResponse.toBinary(response));
}

async function handleTokenAPIGetTokenProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokenRequest, GetTokenResponse>[]
) {
  let request: GetTokenRequest;
  let response: GetTokenResponse;

  try {
    request = GetTokenRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenRequest,
      GetTokenResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetToken(ctx, inputReq);
    });
  } else {
    response = await service.GetToken(ctx, request!);
  }

  return Buffer.from(GetTokenResponse.toBinary(response));
}

async function handleTokenAPIGetTokenLocationsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenLocationsRequest,
    GetTokenLocationsResponse
  >[]
) {
  let request: GetTokenLocationsRequest;
  let response: GetTokenLocationsResponse;

  try {
    request = GetTokenLocationsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenLocationsRequest,
      GetTokenLocationsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenLocations(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenLocations(ctx, request!);
  }

  return Buffer.from(GetTokenLocationsResponse.toBinary(response));
}

async function handleTokenAPIGetTokensMeanTimeToRemediationProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokensMeanTimeToRemediationRequest,
    GetTokensMeanTimeToRemediationResponse
  >[]
) {
  let request: GetTokensMeanTimeToRemediationRequest;
  let response: GetTokensMeanTimeToRemediationResponse;

  try {
    request = GetTokensMeanTimeToRemediationRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokensMeanTimeToRemediationRequest,
      GetTokensMeanTimeToRemediationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokensMeanTimeToRemediation(ctx, inputReq);
    });
  } else {
    response = await service.GetTokensMeanTimeToRemediation(ctx, request!);
  }

  return Buffer.from(GetTokensMeanTimeToRemediationResponse.toBinary(response));
}

async function handleTokenAPIResolveTokenProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ResolveTokenRequest, ResolveTokenResponse>[]
) {
  let request: ResolveTokenRequest;
  let response: ResolveTokenResponse;

  try {
    request = ResolveTokenRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ResolveTokenRequest,
      ResolveTokenResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ResolveToken(ctx, inputReq);
    });
  } else {
    response = await service.ResolveToken(ctx, request!);
  }

  return Buffer.from(ResolveTokenResponse.toBinary(response));
}

async function handleTokenAPIResolveTokensProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ResolveTokensRequest, ResolveTokensResponse>[]
) {
  let request: ResolveTokensRequest;
  let response: ResolveTokensResponse;

  try {
    request = ResolveTokensRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ResolveTokensRequest,
      ResolveTokensResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ResolveTokens(ctx, inputReq);
    });
  } else {
    response = await service.ResolveTokens(ctx, request!);
  }

  return Buffer.from(ResolveTokensResponse.toBinary(response));
}

async function handleTokenAPIGetTokenCountsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTokenCountsRequest, GetTokenCountsResponse>[]
) {
  let request: GetTokenCountsRequest;
  let response: GetTokenCountsResponse;

  try {
    request = GetTokenCountsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenCountsRequest,
      GetTokenCountsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenCounts(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenCounts(ctx, request!);
  }

  return Buffer.from(GetTokenCountsResponse.toBinary(response));
}

async function handleTokenAPIGetTokenGroupByCountsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenGroupByCountsRequest,
    GetTokenGroupByCountsResponse
  >[]
) {
  let request: GetTokenGroupByCountsRequest;
  let response: GetTokenGroupByCountsResponse;

  try {
    request = GetTokenGroupByCountsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenGroupByCountsRequest,
      GetTokenGroupByCountsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenGroupByCounts(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenGroupByCounts(ctx, request!);
  }

  return Buffer.from(GetTokenGroupByCountsResponse.toBinary(response));
}

async function handleTokenAPIGetTokenTypesInfoProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypesInfoRequest,
    GetTokenTypesInfoResponse
  >[]
) {
  let request: GetTokenTypesInfoRequest;
  let response: GetTokenTypesInfoResponse;

  try {
    request = GetTokenTypesInfoRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenTypesInfoRequest,
      GetTokenTypesInfoResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenTypesInfo(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenTypesInfo(ctx, request!);
  }

  return Buffer.from(GetTokenTypesInfoResponse.toBinary(response));
}

async function handleTokenAPIValidateEnabledReposProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ValidateEnabledReposRequest,
    ValidateEnabledReposResponse
  >[]
) {
  let request: ValidateEnabledReposRequest;
  let response: ValidateEnabledReposResponse;

  try {
    request = ValidateEnabledReposRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ValidateEnabledReposRequest,
      ValidateEnabledReposResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ValidateEnabledRepos(ctx, inputReq);
    });
  } else {
    response = await service.ValidateEnabledRepos(ctx, request!);
  }

  return Buffer.from(ValidateEnabledReposResponse.toBinary(response));
}

async function handleTokenAPIAddTokenRemediationProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddTokenRemediationRequest, Empty>[]
) {
  let request: AddTokenRemediationRequest;
  let response: Empty;

  try {
    request = AddTokenRemediationRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      AddTokenRemediationRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddTokenRemediation(ctx, inputReq);
    });
  } else {
    response = await service.AddTokenRemediation(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleTokenAPIGetTokenLatestRemediationProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenLatestRemediationRequest,
    GetTokenLatestRemediationResponse
  >[]
) {
  let request: GetTokenLatestRemediationRequest;
  let response: GetTokenLatestRemediationResponse;

  try {
    request = GetTokenLatestRemediationRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenLatestRemediationRequest,
      GetTokenLatestRemediationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenLatestRemediation(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenLatestRemediation(ctx, request!);
  }

  return Buffer.from(GetTokenLatestRemediationResponse.toBinary(response));
}

async function handleTokenAPIGetTimelineProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTimelineRequest, GetTimelineResponse>[]
) {
  let request: GetTimelineRequest;
  let response: GetTimelineResponse;

  try {
    request = GetTimelineRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTimelineRequest,
      GetTimelineResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTimeline(ctx, inputReq);
    });
  } else {
    response = await service.GetTimeline(ctx, request!);
  }

  return Buffer.from(GetTimelineResponse.toBinary(response));
}

async function handleTokenAPIGetMoreTimelineEventsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetMoreTimelineEventsRequest,
    GetMoreTimelineEventsResponse
  >[]
) {
  let request: GetMoreTimelineEventsRequest;
  let response: GetMoreTimelineEventsResponse;

  try {
    request = GetMoreTimelineEventsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetMoreTimelineEventsRequest,
      GetMoreTimelineEventsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetMoreTimelineEvents(ctx, inputReq);
    });
  } else {
    response = await service.GetMoreTimelineEvents(ctx, request!);
  }

  return Buffer.from(GetMoreTimelineEventsResponse.toBinary(response));
}

async function handleTokenAPIGetTokenValidationStatusProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenValidationStatusRequest,
    GetTokenValidationStatusResponse
  >[]
) {
  let request: GetTokenValidationStatusRequest;
  let response: GetTokenValidationStatusResponse;

  try {
    request = GetTokenValidationStatusRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenValidationStatusRequest,
      GetTokenValidationStatusResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenValidationStatus(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenValidationStatus(ctx, request!);
  }

  return Buffer.from(GetTokenValidationStatusResponse.toBinary(response));
}

async function handleTokenAPIReportTokenProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ReportTokenRequest, ReportTokenResponse>[]
) {
  let request: ReportTokenRequest;
  let response: ReportTokenResponse;

  try {
    request = ReportTokenRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ReportTokenRequest,
      ReportTokenResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ReportToken(ctx, inputReq);
    });
  } else {
    response = await service.ReportToken(ctx, request!);
  }

  return Buffer.from(ReportTokenResponse.toBinary(response));
}

async function handleTokenAPIGetAdversarialAuditProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAdversarialAuditRequest,
    GetAdversarialAuditResponse
  >[]
) {
  let request: GetAdversarialAuditRequest;
  let response: GetAdversarialAuditResponse;

  try {
    request = GetAdversarialAuditRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetAdversarialAuditRequest,
      GetAdversarialAuditResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAdversarialAudit(ctx, inputReq);
    });
  } else {
    response = await service.GetAdversarialAudit(ctx, request!);
  }

  return Buffer.from(GetAdversarialAuditResponse.toBinary(response));
}

async function handleTokenAPIGetWorkflowAuditProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetWorkflowAuditRequest,
    GetWorkflowAuditResponse
  >[]
) {
  let request: GetWorkflowAuditRequest;
  let response: GetWorkflowAuditResponse;

  try {
    request = GetWorkflowAuditRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetWorkflowAuditRequest,
      GetWorkflowAuditResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetWorkflowAudit(ctx, inputReq);
    });
  } else {
    response = await service.GetWorkflowAudit(ctx, request!);
  }

  return Buffer.from(GetWorkflowAuditResponse.toBinary(response));
}

async function handleTokenAPIGetPermissionAuditProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPermissionAuditRequest,
    GetPermissionAuditResponse
  >[]
) {
  let request: GetPermissionAuditRequest;
  let response: GetPermissionAuditResponse;

  try {
    request = GetPermissionAuditRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetPermissionAuditRequest,
      GetPermissionAuditResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPermissionAudit(ctx, inputReq);
    });
  } else {
    response = await service.GetPermissionAudit(ctx, request!);
  }

  return Buffer.from(GetPermissionAuditResponse.toBinary(response));
}

async function handleTokenAPIGetAutofixSuggestionProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAutofixSuggestionRequest,
    GetAutofixSuggestionResponse
  >[]
) {
  let request: GetAutofixSuggestionRequest;
  let response: GetAutofixSuggestionResponse;

  try {
    request = GetAutofixSuggestionRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetAutofixSuggestionRequest,
      GetAutofixSuggestionResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAutofixSuggestion(ctx, inputReq);
    });
  } else {
    response = await service.GetAutofixSuggestion(ctx, request!);
  }

  return Buffer.from(GetAutofixSuggestionResponse.toBinary(response));
}

async function handleTokenAPIUpdateTokenWithClosureExemptionRequestIdProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateTokenWithClosureExemptionRequestIdRequest,
    Empty
  >[]
) {
  let request: UpdateTokenWithClosureExemptionRequestIdRequest;
  let response: Empty;

  try {
    request = UpdateTokenWithClosureExemptionRequestIdRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UpdateTokenWithClosureExemptionRequestIdRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateTokenWithClosureExemptionRequestId(ctx, inputReq);
    });
  } else {
    response = await service.UpdateTokenWithClosureExemptionRequestId(
      ctx,
      request!
    );
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleTokenAPISetAlertAssigneeProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, SetAlertAssigneeRequest, Empty>[]
) {
  let request: SetAlertAssigneeRequest;
  let response: Empty;

  try {
    request = SetAlertAssigneeRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      SetAlertAssigneeRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.SetAlertAssignee(ctx, inputReq);
    });
  } else {
    response = await service.SetAlertAssignee(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleTokenAPISetAlertValidityProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, SetAlertValidityRequest, Empty>[]
) {
  let request: SetAlertValidityRequest;
  let response: Empty;

  try {
    request = SetAlertValidityRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      SetAlertValidityRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.SetAlertValidity(ctx, inputReq);
    });
  } else {
    response = await service.SetAlertValidity(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleTokenAPISetCampaignAssignmentsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CampaignAssignmentsRequest,
    CampaignAssignmentsResponse
  >[]
) {
  let request: CampaignAssignmentsRequest;
  let response: CampaignAssignmentsResponse;

  try {
    request = CampaignAssignmentsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CampaignAssignmentsRequest,
      CampaignAssignmentsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.SetCampaignAssignments(ctx, inputReq);
    });
  } else {
    response = await service.SetCampaignAssignments(ctx, request!);
  }

  return Buffer.from(CampaignAssignmentsResponse.toBinary(response));
}

async function handleTokenAPIGetTokenMetadataProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenMetadataRequest,
    GetTokenMetadataResponse
  >[]
) {
  let request: GetTokenMetadataRequest;
  let response: GetTokenMetadataResponse;

  try {
    request = GetTokenMetadataRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenMetadataRequest,
      GetTokenMetadataResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenMetadata(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenMetadata(ctx, request!);
  }

  return Buffer.from(GetTokenMetadataResponse.toBinary(response));
}

async function handleTokenAPIDeleteCampaignProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TokenAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CampaignDeletionRequest,
    CampaignDeletionResponse
  >[]
) {
  let request: CampaignDeletionRequest;
  let response: CampaignDeletionResponse;

  try {
    request = CampaignDeletionRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CampaignDeletionRequest,
      CampaignDeletionResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DeleteCampaign(ctx, inputReq);
    });
  } else {
    response = await service.DeleteCampaign(ctx, request!);
  }

  return Buffer.from(CampaignDeletionResponse.toBinary(response));
}
