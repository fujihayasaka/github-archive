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
  GetAlertsForInsightsBackfillRequest,
  GetAlertsForInsightsBackfillRequestResponse,
  GetTokenAlertMetricsRequest,
  GetTokenAlertMetricsResponse,
  GetTokenPushProtectionMetricsRequest,
  GetTokenPushProtectionMetricsResponse,
  GetPushProtectionMetricsRequest,
  GetPushProtectionMetricsResponse,
  GetPushProtectionMetricsForReposRequest,
  GetPushProtectionMetricsForReposResponse,
  GetBlockCountsByTokenTypeRequest,
  GetBlockCountsByTokenTypeResponse,
  GetBlockCountsByRepoRequest,
  GetBlockCountsByRepoResponse,
  GetBypassCountsByTokenTypeRequest,
  GetBypassCountsByTokenTypeResponse,
  GetBypassCountsByRepoRequest,
  GetBypassCountsByRepoResponse,
} from "./metrics_api";

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

export interface MetricsAPIClient {
  GetAlertsForInsightsBackfill(
    request: GetAlertsForInsightsBackfillRequest
  ): Promise<GetAlertsForInsightsBackfillRequestResponse>;
  GetTokenAlertMetrics(
    request: GetTokenAlertMetricsRequest
  ): Promise<GetTokenAlertMetricsResponse>;
  GetTokenPushProtectionMetrics(
    request: GetTokenPushProtectionMetricsRequest
  ): Promise<GetTokenPushProtectionMetricsResponse>;
  GetPushProtectionMetrics(
    request: GetPushProtectionMetricsRequest
  ): Promise<GetPushProtectionMetricsResponse>;
  GetPushProtectionMetricsForRepos(
    request: GetPushProtectionMetricsForReposRequest
  ): Promise<GetPushProtectionMetricsForReposResponse>;
  GetBlockCountsByTokenType(
    request: GetBlockCountsByTokenTypeRequest
  ): Promise<GetBlockCountsByTokenTypeResponse>;
  GetBlockCountsByRepo(
    request: GetBlockCountsByRepoRequest
  ): Promise<GetBlockCountsByRepoResponse>;
  GetBypassCountsByTokenType(
    request: GetBypassCountsByTokenTypeRequest
  ): Promise<GetBypassCountsByTokenTypeResponse>;
  GetBypassCountsByRepo(
    request: GetBypassCountsByRepoRequest
  ): Promise<GetBypassCountsByRepoResponse>;
}

export class MetricsAPIClientJSON implements MetricsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetAlertsForInsightsBackfill.bind(this);
    this.GetTokenAlertMetrics.bind(this);
    this.GetTokenPushProtectionMetrics.bind(this);
    this.GetPushProtectionMetrics.bind(this);
    this.GetPushProtectionMetricsForRepos.bind(this);
    this.GetBlockCountsByTokenType.bind(this);
    this.GetBlockCountsByRepo.bind(this);
    this.GetBypassCountsByTokenType.bind(this);
    this.GetBypassCountsByRepo.bind(this);
  }
  GetAlertsForInsightsBackfill(
    request: GetAlertsForInsightsBackfillRequest
  ): Promise<GetAlertsForInsightsBackfillRequestResponse> {
    const data = GetAlertsForInsightsBackfillRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetAlertsForInsightsBackfill",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetAlertsForInsightsBackfillRequestResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenAlertMetrics(
    request: GetTokenAlertMetricsRequest
  ): Promise<GetTokenAlertMetricsResponse> {
    const data = GetTokenAlertMetricsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetTokenAlertMetrics",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenAlertMetricsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenPushProtectionMetrics(
    request: GetTokenPushProtectionMetricsRequest
  ): Promise<GetTokenPushProtectionMetricsResponse> {
    const data = GetTokenPushProtectionMetricsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetTokenPushProtectionMetrics",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenPushProtectionMetricsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetPushProtectionMetrics(
    request: GetPushProtectionMetricsRequest
  ): Promise<GetPushProtectionMetricsResponse> {
    const data = GetPushProtectionMetricsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetPushProtectionMetrics",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetPushProtectionMetricsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetPushProtectionMetricsForRepos(
    request: GetPushProtectionMetricsForReposRequest
  ): Promise<GetPushProtectionMetricsForReposResponse> {
    const data = GetPushProtectionMetricsForReposRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetPushProtectionMetricsForRepos",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetPushProtectionMetricsForReposResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetBlockCountsByTokenType(
    request: GetBlockCountsByTokenTypeRequest
  ): Promise<GetBlockCountsByTokenTypeResponse> {
    const data = GetBlockCountsByTokenTypeRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBlockCountsByTokenType",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBlockCountsByTokenTypeResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetBlockCountsByRepo(
    request: GetBlockCountsByRepoRequest
  ): Promise<GetBlockCountsByRepoResponse> {
    const data = GetBlockCountsByRepoRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBlockCountsByRepo",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBlockCountsByRepoResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetBypassCountsByTokenType(
    request: GetBypassCountsByTokenTypeRequest
  ): Promise<GetBypassCountsByTokenTypeResponse> {
    const data = GetBypassCountsByTokenTypeRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBypassCountsByTokenType",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBypassCountsByTokenTypeResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetBypassCountsByRepo(
    request: GetBypassCountsByRepoRequest
  ): Promise<GetBypassCountsByRepoResponse> {
    const data = GetBypassCountsByRepoRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBypassCountsByRepo",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBypassCountsByRepoResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class MetricsAPIClientProtobuf implements MetricsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetAlertsForInsightsBackfill.bind(this);
    this.GetTokenAlertMetrics.bind(this);
    this.GetTokenPushProtectionMetrics.bind(this);
    this.GetPushProtectionMetrics.bind(this);
    this.GetPushProtectionMetricsForRepos.bind(this);
    this.GetBlockCountsByTokenType.bind(this);
    this.GetBlockCountsByRepo.bind(this);
    this.GetBypassCountsByTokenType.bind(this);
    this.GetBypassCountsByRepo.bind(this);
  }
  GetAlertsForInsightsBackfill(
    request: GetAlertsForInsightsBackfillRequest
  ): Promise<GetAlertsForInsightsBackfillRequestResponse> {
    const data = GetAlertsForInsightsBackfillRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetAlertsForInsightsBackfill",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetAlertsForInsightsBackfillRequestResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenAlertMetrics(
    request: GetTokenAlertMetricsRequest
  ): Promise<GetTokenAlertMetricsResponse> {
    const data = GetTokenAlertMetricsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetTokenAlertMetrics",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenAlertMetricsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenPushProtectionMetrics(
    request: GetTokenPushProtectionMetricsRequest
  ): Promise<GetTokenPushProtectionMetricsResponse> {
    const data = GetTokenPushProtectionMetricsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetTokenPushProtectionMetrics",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenPushProtectionMetricsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetPushProtectionMetrics(
    request: GetPushProtectionMetricsRequest
  ): Promise<GetPushProtectionMetricsResponse> {
    const data = GetPushProtectionMetricsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetPushProtectionMetrics",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetPushProtectionMetricsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetPushProtectionMetricsForRepos(
    request: GetPushProtectionMetricsForReposRequest
  ): Promise<GetPushProtectionMetricsForReposResponse> {
    const data = GetPushProtectionMetricsForReposRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetPushProtectionMetricsForRepos",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetPushProtectionMetricsForReposResponse.fromBinary(data as Uint8Array)
    );
  }

  GetBlockCountsByTokenType(
    request: GetBlockCountsByTokenTypeRequest
  ): Promise<GetBlockCountsByTokenTypeResponse> {
    const data = GetBlockCountsByTokenTypeRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBlockCountsByTokenType",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBlockCountsByTokenTypeResponse.fromBinary(data as Uint8Array)
    );
  }

  GetBlockCountsByRepo(
    request: GetBlockCountsByRepoRequest
  ): Promise<GetBlockCountsByRepoResponse> {
    const data = GetBlockCountsByRepoRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBlockCountsByRepo",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBlockCountsByRepoResponse.fromBinary(data as Uint8Array)
    );
  }

  GetBypassCountsByTokenType(
    request: GetBypassCountsByTokenTypeRequest
  ): Promise<GetBypassCountsByTokenTypeResponse> {
    const data = GetBypassCountsByTokenTypeRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBypassCountsByTokenType",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBypassCountsByTokenTypeResponse.fromBinary(data as Uint8Array)
    );
  }

  GetBypassCountsByRepo(
    request: GetBypassCountsByRepoRequest
  ): Promise<GetBypassCountsByRepoResponse> {
    const data = GetBypassCountsByRepoRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.metrics.v1.MetricsAPI",
      "GetBypassCountsByRepo",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBypassCountsByRepoResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface MetricsAPITwirp<T extends TwirpContext = TwirpContext> {
  GetAlertsForInsightsBackfill(
    ctx: T,
    request: GetAlertsForInsightsBackfillRequest
  ): Promise<GetAlertsForInsightsBackfillRequestResponse>;
  GetTokenAlertMetrics(
    ctx: T,
    request: GetTokenAlertMetricsRequest
  ): Promise<GetTokenAlertMetricsResponse>;
  GetTokenPushProtectionMetrics(
    ctx: T,
    request: GetTokenPushProtectionMetricsRequest
  ): Promise<GetTokenPushProtectionMetricsResponse>;
  GetPushProtectionMetrics(
    ctx: T,
    request: GetPushProtectionMetricsRequest
  ): Promise<GetPushProtectionMetricsResponse>;
  GetPushProtectionMetricsForRepos(
    ctx: T,
    request: GetPushProtectionMetricsForReposRequest
  ): Promise<GetPushProtectionMetricsForReposResponse>;
  GetBlockCountsByTokenType(
    ctx: T,
    request: GetBlockCountsByTokenTypeRequest
  ): Promise<GetBlockCountsByTokenTypeResponse>;
  GetBlockCountsByRepo(
    ctx: T,
    request: GetBlockCountsByRepoRequest
  ): Promise<GetBlockCountsByRepoResponse>;
  GetBypassCountsByTokenType(
    ctx: T,
    request: GetBypassCountsByTokenTypeRequest
  ): Promise<GetBypassCountsByTokenTypeResponse>;
  GetBypassCountsByRepo(
    ctx: T,
    request: GetBypassCountsByRepoRequest
  ): Promise<GetBypassCountsByRepoResponse>;
}

export enum MetricsAPIMethod {
  GetAlertsForInsightsBackfill = "GetAlertsForInsightsBackfill",
  GetTokenAlertMetrics = "GetTokenAlertMetrics",
  GetTokenPushProtectionMetrics = "GetTokenPushProtectionMetrics",
  GetPushProtectionMetrics = "GetPushProtectionMetrics",
  GetPushProtectionMetricsForRepos = "GetPushProtectionMetricsForRepos",
  GetBlockCountsByTokenType = "GetBlockCountsByTokenType",
  GetBlockCountsByRepo = "GetBlockCountsByRepo",
  GetBypassCountsByTokenType = "GetBypassCountsByTokenType",
  GetBypassCountsByRepo = "GetBypassCountsByRepo",
}

export const MetricsAPIMethodList = [
  MetricsAPIMethod.GetAlertsForInsightsBackfill,
  MetricsAPIMethod.GetTokenAlertMetrics,
  MetricsAPIMethod.GetTokenPushProtectionMetrics,
  MetricsAPIMethod.GetPushProtectionMetrics,
  MetricsAPIMethod.GetPushProtectionMetricsForRepos,
  MetricsAPIMethod.GetBlockCountsByTokenType,
  MetricsAPIMethod.GetBlockCountsByRepo,
  MetricsAPIMethod.GetBypassCountsByTokenType,
  MetricsAPIMethod.GetBypassCountsByRepo,
];

export function createMetricsAPIServer<T extends TwirpContext = TwirpContext>(
  service: MetricsAPITwirp<T>
) {
  return new TwirpServer<MetricsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.metrics.v1",
    serviceName: "MetricsAPI",
    methodList: MetricsAPIMethodList,
    matchRoute: matchMetricsAPIRoute,
  });
}

function matchMetricsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetAlertsForInsightsBackfill":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetAlertsForInsightsBackfillRequest,
          GetAlertsForInsightsBackfillRequestResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetAlertsForInsightsBackfill" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetAlertsForInsightsBackfillRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenAlertMetrics":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenAlertMetricsRequest,
          GetTokenAlertMetricsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenAlertMetrics" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetTokenAlertMetricsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenPushProtectionMetrics":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenPushProtectionMetricsRequest,
          GetTokenPushProtectionMetricsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenPushProtectionMetrics" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetTokenPushProtectionMetricsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetPushProtectionMetrics":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetPushProtectionMetricsRequest,
          GetPushProtectionMetricsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetPushProtectionMetrics" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetPushProtectionMetricsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetPushProtectionMetricsForRepos":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetPushProtectionMetricsForReposRequest,
          GetPushProtectionMetricsForReposResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetPushProtectionMetricsForRepos" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetPushProtectionMetricsForReposRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetBlockCountsByTokenType":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetBlockCountsByTokenTypeRequest,
          GetBlockCountsByTokenTypeResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetBlockCountsByTokenType" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetBlockCountsByTokenTypeRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetBlockCountsByRepo":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetBlockCountsByRepoRequest,
          GetBlockCountsByRepoResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetBlockCountsByRepo" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetBlockCountsByRepoRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetBypassCountsByTokenType":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetBypassCountsByTokenTypeRequest,
          GetBypassCountsByTokenTypeResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetBypassCountsByTokenType" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetBypassCountsByTokenTypeRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetBypassCountsByRepo":
      return async (
        ctx: T,
        service: MetricsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetBypassCountsByRepoRequest,
          GetBypassCountsByRepoResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetBypassCountsByRepo" };
        await events.onMatch(ctx);
        return handleMetricsAPIGetBypassCountsByRepoRequest(
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

function handleMetricsAPIGetAlertsForInsightsBackfillRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAlertsForInsightsBackfillRequest,
    GetAlertsForInsightsBackfillRequestResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetAlertsForInsightsBackfillJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetAlertsForInsightsBackfillProtobuf<T>(
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

function handleMetricsAPIGetTokenAlertMetricsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenAlertMetricsRequest,
    GetTokenAlertMetricsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetTokenAlertMetricsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetTokenAlertMetricsProtobuf<T>(
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

function handleMetricsAPIGetTokenPushProtectionMetricsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenPushProtectionMetricsRequest,
    GetTokenPushProtectionMetricsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetTokenPushProtectionMetricsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetTokenPushProtectionMetricsProtobuf<T>(
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

function handleMetricsAPIGetPushProtectionMetricsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPushProtectionMetricsRequest,
    GetPushProtectionMetricsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetPushProtectionMetricsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetPushProtectionMetricsProtobuf<T>(
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

function handleMetricsAPIGetPushProtectionMetricsForReposRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPushProtectionMetricsForReposRequest,
    GetPushProtectionMetricsForReposResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetPushProtectionMetricsForReposJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetPushProtectionMetricsForReposProtobuf<T>(
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

function handleMetricsAPIGetBlockCountsByTokenTypeRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBlockCountsByTokenTypeRequest,
    GetBlockCountsByTokenTypeResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetBlockCountsByTokenTypeJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetBlockCountsByTokenTypeProtobuf<T>(
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

function handleMetricsAPIGetBlockCountsByRepoRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBlockCountsByRepoRequest,
    GetBlockCountsByRepoResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetBlockCountsByRepoJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetBlockCountsByRepoProtobuf<T>(
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

function handleMetricsAPIGetBypassCountsByTokenTypeRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassCountsByTokenTypeRequest,
    GetBypassCountsByTokenTypeResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetBypassCountsByTokenTypeJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetBypassCountsByTokenTypeProtobuf<T>(
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

function handleMetricsAPIGetBypassCountsByRepoRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassCountsByRepoRequest,
    GetBypassCountsByRepoResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleMetricsAPIGetBypassCountsByRepoJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleMetricsAPIGetBypassCountsByRepoProtobuf<T>(
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
async function handleMetricsAPIGetAlertsForInsightsBackfillJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAlertsForInsightsBackfillRequest,
    GetAlertsForInsightsBackfillRequestResponse
  >[]
) {
  let request: GetAlertsForInsightsBackfillRequest;
  let response: GetAlertsForInsightsBackfillRequestResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetAlertsForInsightsBackfillRequest.fromJson(body, {
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
      GetAlertsForInsightsBackfillRequest,
      GetAlertsForInsightsBackfillRequestResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAlertsForInsightsBackfill(ctx, inputReq);
    });
  } else {
    response = await service.GetAlertsForInsightsBackfill(ctx, request!);
  }

  return JSON.stringify(
    GetAlertsForInsightsBackfillRequestResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetTokenAlertMetricsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenAlertMetricsRequest,
    GetTokenAlertMetricsResponse
  >[]
) {
  let request: GetTokenAlertMetricsRequest;
  let response: GetTokenAlertMetricsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenAlertMetricsRequest.fromJson(body, {
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
      GetTokenAlertMetricsRequest,
      GetTokenAlertMetricsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenAlertMetrics(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenAlertMetrics(ctx, request!);
  }

  return JSON.stringify(
    GetTokenAlertMetricsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetTokenPushProtectionMetricsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenPushProtectionMetricsRequest,
    GetTokenPushProtectionMetricsResponse
  >[]
) {
  let request: GetTokenPushProtectionMetricsRequest;
  let response: GetTokenPushProtectionMetricsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenPushProtectionMetricsRequest.fromJson(body, {
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
      GetTokenPushProtectionMetricsRequest,
      GetTokenPushProtectionMetricsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenPushProtectionMetrics(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenPushProtectionMetrics(ctx, request!);
  }

  return JSON.stringify(
    GetTokenPushProtectionMetricsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetPushProtectionMetricsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPushProtectionMetricsRequest,
    GetPushProtectionMetricsResponse
  >[]
) {
  let request: GetPushProtectionMetricsRequest;
  let response: GetPushProtectionMetricsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetPushProtectionMetricsRequest.fromJson(body, {
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
      GetPushProtectionMetricsRequest,
      GetPushProtectionMetricsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPushProtectionMetrics(ctx, inputReq);
    });
  } else {
    response = await service.GetPushProtectionMetrics(ctx, request!);
  }

  return JSON.stringify(
    GetPushProtectionMetricsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetPushProtectionMetricsForReposJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPushProtectionMetricsForReposRequest,
    GetPushProtectionMetricsForReposResponse
  >[]
) {
  let request: GetPushProtectionMetricsForReposRequest;
  let response: GetPushProtectionMetricsForReposResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetPushProtectionMetricsForReposRequest.fromJson(body, {
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
      GetPushProtectionMetricsForReposRequest,
      GetPushProtectionMetricsForReposResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPushProtectionMetricsForRepos(ctx, inputReq);
    });
  } else {
    response = await service.GetPushProtectionMetricsForRepos(ctx, request!);
  }

  return JSON.stringify(
    GetPushProtectionMetricsForReposResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetBlockCountsByTokenTypeJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBlockCountsByTokenTypeRequest,
    GetBlockCountsByTokenTypeResponse
  >[]
) {
  let request: GetBlockCountsByTokenTypeRequest;
  let response: GetBlockCountsByTokenTypeResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBlockCountsByTokenTypeRequest.fromJson(body, {
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
      GetBlockCountsByTokenTypeRequest,
      GetBlockCountsByTokenTypeResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBlockCountsByTokenType(ctx, inputReq);
    });
  } else {
    response = await service.GetBlockCountsByTokenType(ctx, request!);
  }

  return JSON.stringify(
    GetBlockCountsByTokenTypeResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetBlockCountsByRepoJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBlockCountsByRepoRequest,
    GetBlockCountsByRepoResponse
  >[]
) {
  let request: GetBlockCountsByRepoRequest;
  let response: GetBlockCountsByRepoResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBlockCountsByRepoRequest.fromJson(body, {
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
      GetBlockCountsByRepoRequest,
      GetBlockCountsByRepoResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBlockCountsByRepo(ctx, inputReq);
    });
  } else {
    response = await service.GetBlockCountsByRepo(ctx, request!);
  }

  return JSON.stringify(
    GetBlockCountsByRepoResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetBypassCountsByTokenTypeJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassCountsByTokenTypeRequest,
    GetBypassCountsByTokenTypeResponse
  >[]
) {
  let request: GetBypassCountsByTokenTypeRequest;
  let response: GetBypassCountsByTokenTypeResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBypassCountsByTokenTypeRequest.fromJson(body, {
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
      GetBypassCountsByTokenTypeRequest,
      GetBypassCountsByTokenTypeResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassCountsByTokenType(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassCountsByTokenType(ctx, request!);
  }

  return JSON.stringify(
    GetBypassCountsByTokenTypeResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleMetricsAPIGetBypassCountsByRepoJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassCountsByRepoRequest,
    GetBypassCountsByRepoResponse
  >[]
) {
  let request: GetBypassCountsByRepoRequest;
  let response: GetBypassCountsByRepoResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBypassCountsByRepoRequest.fromJson(body, {
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
      GetBypassCountsByRepoRequest,
      GetBypassCountsByRepoResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassCountsByRepo(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassCountsByRepo(ctx, request!);
  }

  return JSON.stringify(
    GetBypassCountsByRepoResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleMetricsAPIGetAlertsForInsightsBackfillProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetAlertsForInsightsBackfillRequest,
    GetAlertsForInsightsBackfillRequestResponse
  >[]
) {
  let request: GetAlertsForInsightsBackfillRequest;
  let response: GetAlertsForInsightsBackfillRequestResponse;

  try {
    request = GetAlertsForInsightsBackfillRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetAlertsForInsightsBackfillRequest,
      GetAlertsForInsightsBackfillRequestResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAlertsForInsightsBackfill(ctx, inputReq);
    });
  } else {
    response = await service.GetAlertsForInsightsBackfill(ctx, request!);
  }

  return Buffer.from(
    GetAlertsForInsightsBackfillRequestResponse.toBinary(response)
  );
}

async function handleMetricsAPIGetTokenAlertMetricsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenAlertMetricsRequest,
    GetTokenAlertMetricsResponse
  >[]
) {
  let request: GetTokenAlertMetricsRequest;
  let response: GetTokenAlertMetricsResponse;

  try {
    request = GetTokenAlertMetricsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenAlertMetricsRequest,
      GetTokenAlertMetricsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenAlertMetrics(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenAlertMetrics(ctx, request!);
  }

  return Buffer.from(GetTokenAlertMetricsResponse.toBinary(response));
}

async function handleMetricsAPIGetTokenPushProtectionMetricsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenPushProtectionMetricsRequest,
    GetTokenPushProtectionMetricsResponse
  >[]
) {
  let request: GetTokenPushProtectionMetricsRequest;
  let response: GetTokenPushProtectionMetricsResponse;

  try {
    request = GetTokenPushProtectionMetricsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenPushProtectionMetricsRequest,
      GetTokenPushProtectionMetricsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenPushProtectionMetrics(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenPushProtectionMetrics(ctx, request!);
  }

  return Buffer.from(GetTokenPushProtectionMetricsResponse.toBinary(response));
}

async function handleMetricsAPIGetPushProtectionMetricsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPushProtectionMetricsRequest,
    GetPushProtectionMetricsResponse
  >[]
) {
  let request: GetPushProtectionMetricsRequest;
  let response: GetPushProtectionMetricsResponse;

  try {
    request = GetPushProtectionMetricsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetPushProtectionMetricsRequest,
      GetPushProtectionMetricsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPushProtectionMetrics(ctx, inputReq);
    });
  } else {
    response = await service.GetPushProtectionMetrics(ctx, request!);
  }

  return Buffer.from(GetPushProtectionMetricsResponse.toBinary(response));
}

async function handleMetricsAPIGetPushProtectionMetricsForReposProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPushProtectionMetricsForReposRequest,
    GetPushProtectionMetricsForReposResponse
  >[]
) {
  let request: GetPushProtectionMetricsForReposRequest;
  let response: GetPushProtectionMetricsForReposResponse;

  try {
    request = GetPushProtectionMetricsForReposRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetPushProtectionMetricsForReposRequest,
      GetPushProtectionMetricsForReposResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPushProtectionMetricsForRepos(ctx, inputReq);
    });
  } else {
    response = await service.GetPushProtectionMetricsForRepos(ctx, request!);
  }

  return Buffer.from(
    GetPushProtectionMetricsForReposResponse.toBinary(response)
  );
}

async function handleMetricsAPIGetBlockCountsByTokenTypeProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBlockCountsByTokenTypeRequest,
    GetBlockCountsByTokenTypeResponse
  >[]
) {
  let request: GetBlockCountsByTokenTypeRequest;
  let response: GetBlockCountsByTokenTypeResponse;

  try {
    request = GetBlockCountsByTokenTypeRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBlockCountsByTokenTypeRequest,
      GetBlockCountsByTokenTypeResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBlockCountsByTokenType(ctx, inputReq);
    });
  } else {
    response = await service.GetBlockCountsByTokenType(ctx, request!);
  }

  return Buffer.from(GetBlockCountsByTokenTypeResponse.toBinary(response));
}

async function handleMetricsAPIGetBlockCountsByRepoProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBlockCountsByRepoRequest,
    GetBlockCountsByRepoResponse
  >[]
) {
  let request: GetBlockCountsByRepoRequest;
  let response: GetBlockCountsByRepoResponse;

  try {
    request = GetBlockCountsByRepoRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBlockCountsByRepoRequest,
      GetBlockCountsByRepoResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBlockCountsByRepo(ctx, inputReq);
    });
  } else {
    response = await service.GetBlockCountsByRepo(ctx, request!);
  }

  return Buffer.from(GetBlockCountsByRepoResponse.toBinary(response));
}

async function handleMetricsAPIGetBypassCountsByTokenTypeProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassCountsByTokenTypeRequest,
    GetBypassCountsByTokenTypeResponse
  >[]
) {
  let request: GetBypassCountsByTokenTypeRequest;
  let response: GetBypassCountsByTokenTypeResponse;

  try {
    request = GetBypassCountsByTokenTypeRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBypassCountsByTokenTypeRequest,
      GetBypassCountsByTokenTypeResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassCountsByTokenType(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassCountsByTokenType(ctx, request!);
  }

  return Buffer.from(GetBypassCountsByTokenTypeResponse.toBinary(response));
}

async function handleMetricsAPIGetBypassCountsByRepoProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: MetricsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassCountsByRepoRequest,
    GetBypassCountsByRepoResponse
  >[]
) {
  let request: GetBypassCountsByRepoRequest;
  let response: GetBypassCountsByRepoResponse;

  try {
    request = GetBypassCountsByRepoRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBypassCountsByRepoRequest,
      GetBypassCountsByRepoResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassCountsByRepo(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassCountsByRepo(ctx, request!);
  }

  return Buffer.from(GetBypassCountsByRepoResponse.toBinary(response));
}
