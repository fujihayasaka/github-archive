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
  CancelDryRunsForCustomPatternRequest,
  DryRunMetadataForPatternRequest,
  DryRunMetadataForPatternResponse,
  DryRunResultsRequest,
  DryRunResultsResponse,
} from "./dry_runs_api";
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

export interface DryRunsAPIClient {
  CancelDryRunsForCustomPattern(
    request: CancelDryRunsForCustomPatternRequest
  ): Promise<Empty>;
  DryRunMetadataForPattern(
    request: DryRunMetadataForPatternRequest
  ): Promise<DryRunMetadataForPatternResponse>;
  DryRunResultsForPattern(
    request: DryRunResultsRequest
  ): Promise<DryRunResultsResponse>;
}

export class DryRunsAPIClientJSON implements DryRunsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.CancelDryRunsForCustomPattern.bind(this);
    this.DryRunMetadataForPattern.bind(this);
    this.DryRunResultsForPattern.bind(this);
  }
  CancelDryRunsForCustomPattern(
    request: CancelDryRunsForCustomPatternRequest
  ): Promise<Empty> {
    const data = CancelDryRunsForCustomPatternRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.DryRunsAPI",
      "CancelDryRunsForCustomPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  DryRunMetadataForPattern(
    request: DryRunMetadataForPatternRequest
  ): Promise<DryRunMetadataForPatternResponse> {
    const data = DryRunMetadataForPatternRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.DryRunsAPI",
      "DryRunMetadataForPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      DryRunMetadataForPatternResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  DryRunResultsForPattern(
    request: DryRunResultsRequest
  ): Promise<DryRunResultsResponse> {
    const data = DryRunResultsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.DryRunsAPI",
      "DryRunResultsForPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      DryRunResultsResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class DryRunsAPIClientProtobuf implements DryRunsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.CancelDryRunsForCustomPattern.bind(this);
    this.DryRunMetadataForPattern.bind(this);
    this.DryRunResultsForPattern.bind(this);
  }
  CancelDryRunsForCustomPattern(
    request: CancelDryRunsForCustomPatternRequest
  ): Promise<Empty> {
    const data = CancelDryRunsForCustomPatternRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.DryRunsAPI",
      "CancelDryRunsForCustomPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  DryRunMetadataForPattern(
    request: DryRunMetadataForPatternRequest
  ): Promise<DryRunMetadataForPatternResponse> {
    const data = DryRunMetadataForPatternRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.DryRunsAPI",
      "DryRunMetadataForPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      DryRunMetadataForPatternResponse.fromBinary(data as Uint8Array)
    );
  }

  DryRunResultsForPattern(
    request: DryRunResultsRequest
  ): Promise<DryRunResultsResponse> {
    const data = DryRunResultsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.DryRunsAPI",
      "DryRunResultsForPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      DryRunResultsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface DryRunsAPITwirp<T extends TwirpContext = TwirpContext> {
  CancelDryRunsForCustomPattern(
    ctx: T,
    request: CancelDryRunsForCustomPatternRequest
  ): Promise<Empty>;
  DryRunMetadataForPattern(
    ctx: T,
    request: DryRunMetadataForPatternRequest
  ): Promise<DryRunMetadataForPatternResponse>;
  DryRunResultsForPattern(
    ctx: T,
    request: DryRunResultsRequest
  ): Promise<DryRunResultsResponse>;
}

export enum DryRunsAPIMethod {
  CancelDryRunsForCustomPattern = "CancelDryRunsForCustomPattern",
  DryRunMetadataForPattern = "DryRunMetadataForPattern",
  DryRunResultsForPattern = "DryRunResultsForPattern",
}

export const DryRunsAPIMethodList = [
  DryRunsAPIMethod.CancelDryRunsForCustomPattern,
  DryRunsAPIMethod.DryRunMetadataForPattern,
  DryRunsAPIMethod.DryRunResultsForPattern,
];

export function createDryRunsAPIServer<T extends TwirpContext = TwirpContext>(
  service: DryRunsAPITwirp<T>
) {
  return new TwirpServer<DryRunsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "DryRunsAPI",
    methodList: DryRunsAPIMethodList,
    matchRoute: matchDryRunsAPIRoute,
  });
}

function matchDryRunsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "CancelDryRunsForCustomPattern":
      return async (
        ctx: T,
        service: DryRunsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          CancelDryRunsForCustomPatternRequest,
          Empty
        >[]
      ) => {
        ctx = { ...ctx, methodName: "CancelDryRunsForCustomPattern" };
        await events.onMatch(ctx);
        return handleDryRunsAPICancelDryRunsForCustomPatternRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "DryRunMetadataForPattern":
      return async (
        ctx: T,
        service: DryRunsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          DryRunMetadataForPatternRequest,
          DryRunMetadataForPatternResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "DryRunMetadataForPattern" };
        await events.onMatch(ctx);
        return handleDryRunsAPIDryRunMetadataForPatternRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "DryRunResultsForPattern":
      return async (
        ctx: T,
        service: DryRunsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          DryRunResultsRequest,
          DryRunResultsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "DryRunResultsForPattern" };
        await events.onMatch(ctx);
        return handleDryRunsAPIDryRunResultsForPatternRequest(
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

function handleDryRunsAPICancelDryRunsForCustomPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, CancelDryRunsForCustomPatternRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleDryRunsAPICancelDryRunsForCustomPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleDryRunsAPICancelDryRunsForCustomPatternProtobuf<T>(
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

function handleDryRunsAPIDryRunMetadataForPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    DryRunMetadataForPatternRequest,
    DryRunMetadataForPatternResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleDryRunsAPIDryRunMetadataForPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleDryRunsAPIDryRunMetadataForPatternProtobuf<T>(
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

function handleDryRunsAPIDryRunResultsForPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, DryRunResultsRequest, DryRunResultsResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleDryRunsAPIDryRunResultsForPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleDryRunsAPIDryRunResultsForPatternProtobuf<T>(
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
async function handleDryRunsAPICancelDryRunsForCustomPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, CancelDryRunsForCustomPatternRequest, Empty>[]
) {
  let request: CancelDryRunsForCustomPatternRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = CancelDryRunsForCustomPatternRequest.fromJson(body, {
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
      CancelDryRunsForCustomPatternRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CancelDryRunsForCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.CancelDryRunsForCustomPattern(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleDryRunsAPIDryRunMetadataForPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    DryRunMetadataForPatternRequest,
    DryRunMetadataForPatternResponse
  >[]
) {
  let request: DryRunMetadataForPatternRequest;
  let response: DryRunMetadataForPatternResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = DryRunMetadataForPatternRequest.fromJson(body, {
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
      DryRunMetadataForPatternRequest,
      DryRunMetadataForPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DryRunMetadataForPattern(ctx, inputReq);
    });
  } else {
    response = await service.DryRunMetadataForPattern(ctx, request!);
  }

  return JSON.stringify(
    DryRunMetadataForPatternResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleDryRunsAPIDryRunResultsForPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, DryRunResultsRequest, DryRunResultsResponse>[]
) {
  let request: DryRunResultsRequest;
  let response: DryRunResultsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = DryRunResultsRequest.fromJson(body, {
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
      DryRunResultsRequest,
      DryRunResultsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DryRunResultsForPattern(ctx, inputReq);
    });
  } else {
    response = await service.DryRunResultsForPattern(ctx, request!);
  }

  return JSON.stringify(
    DryRunResultsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleDryRunsAPICancelDryRunsForCustomPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, CancelDryRunsForCustomPatternRequest, Empty>[]
) {
  let request: CancelDryRunsForCustomPatternRequest;
  let response: Empty;

  try {
    request = CancelDryRunsForCustomPatternRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CancelDryRunsForCustomPatternRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CancelDryRunsForCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.CancelDryRunsForCustomPattern(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleDryRunsAPIDryRunMetadataForPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    DryRunMetadataForPatternRequest,
    DryRunMetadataForPatternResponse
  >[]
) {
  let request: DryRunMetadataForPatternRequest;
  let response: DryRunMetadataForPatternResponse;

  try {
    request = DryRunMetadataForPatternRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      DryRunMetadataForPatternRequest,
      DryRunMetadataForPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DryRunMetadataForPattern(ctx, inputReq);
    });
  } else {
    response = await service.DryRunMetadataForPattern(ctx, request!);
  }

  return Buffer.from(DryRunMetadataForPatternResponse.toBinary(response));
}

async function handleDryRunsAPIDryRunResultsForPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DryRunsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, DryRunResultsRequest, DryRunResultsResponse>[]
) {
  let request: DryRunResultsRequest;
  let response: DryRunResultsResponse;

  try {
    request = DryRunResultsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      DryRunResultsRequest,
      DryRunResultsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DryRunResultsForPattern(ctx, inputReq);
    });
  } else {
    response = await service.DryRunResultsForPattern(ctx, request!);
  }

  return Buffer.from(DryRunResultsResponse.toBinary(response));
}
