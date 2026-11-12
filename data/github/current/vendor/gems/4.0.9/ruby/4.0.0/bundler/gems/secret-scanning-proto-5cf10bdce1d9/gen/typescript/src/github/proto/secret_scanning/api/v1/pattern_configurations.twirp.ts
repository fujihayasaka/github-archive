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
  UpsertPatternConfigurationRequest,
  UpsertPatternConfigurationResponse,
  GetPatternConfigurationByOwnerRequest,
  GetPatternConfigurationByOwnerResponse,
  GetEnabledPatternCountRequest,
  GetEnabledPatternCountResponse,
} from "./pattern_configurations";

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

export interface PatternConfigurationsAPIClient {
  UpsertPatternConfiguration(
    request: UpsertPatternConfigurationRequest
  ): Promise<UpsertPatternConfigurationResponse>;
  GetPatternConfigurationByOwner(
    request: GetPatternConfigurationByOwnerRequest
  ): Promise<GetPatternConfigurationByOwnerResponse>;
  GetEnabledPatternCount(
    request: GetEnabledPatternCountRequest
  ): Promise<GetEnabledPatternCountResponse>;
}

export class PatternConfigurationsAPIClientJSON
  implements PatternConfigurationsAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.UpsertPatternConfiguration.bind(this);
    this.GetPatternConfigurationByOwner.bind(this);
    this.GetEnabledPatternCount.bind(this);
  }
  UpsertPatternConfiguration(
    request: UpsertPatternConfigurationRequest
  ): Promise<UpsertPatternConfigurationResponse> {
    const data = UpsertPatternConfigurationRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.PatternConfigurationsAPI",
      "UpsertPatternConfiguration",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      UpsertPatternConfigurationResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetPatternConfigurationByOwner(
    request: GetPatternConfigurationByOwnerRequest
  ): Promise<GetPatternConfigurationByOwnerResponse> {
    const data = GetPatternConfigurationByOwnerRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.PatternConfigurationsAPI",
      "GetPatternConfigurationByOwner",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetPatternConfigurationByOwnerResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetEnabledPatternCount(
    request: GetEnabledPatternCountRequest
  ): Promise<GetEnabledPatternCountResponse> {
    const data = GetEnabledPatternCountRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.PatternConfigurationsAPI",
      "GetEnabledPatternCount",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetEnabledPatternCountResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class PatternConfigurationsAPIClientProtobuf
  implements PatternConfigurationsAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.UpsertPatternConfiguration.bind(this);
    this.GetPatternConfigurationByOwner.bind(this);
    this.GetEnabledPatternCount.bind(this);
  }
  UpsertPatternConfiguration(
    request: UpsertPatternConfigurationRequest
  ): Promise<UpsertPatternConfigurationResponse> {
    const data = UpsertPatternConfigurationRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.PatternConfigurationsAPI",
      "UpsertPatternConfiguration",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      UpsertPatternConfigurationResponse.fromBinary(data as Uint8Array)
    );
  }

  GetPatternConfigurationByOwner(
    request: GetPatternConfigurationByOwnerRequest
  ): Promise<GetPatternConfigurationByOwnerResponse> {
    const data = GetPatternConfigurationByOwnerRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.PatternConfigurationsAPI",
      "GetPatternConfigurationByOwner",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetPatternConfigurationByOwnerResponse.fromBinary(data as Uint8Array)
    );
  }

  GetEnabledPatternCount(
    request: GetEnabledPatternCountRequest
  ): Promise<GetEnabledPatternCountResponse> {
    const data = GetEnabledPatternCountRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.PatternConfigurationsAPI",
      "GetEnabledPatternCount",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetEnabledPatternCountResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface PatternConfigurationsAPITwirp<
  T extends TwirpContext = TwirpContext
> {
  UpsertPatternConfiguration(
    ctx: T,
    request: UpsertPatternConfigurationRequest
  ): Promise<UpsertPatternConfigurationResponse>;
  GetPatternConfigurationByOwner(
    ctx: T,
    request: GetPatternConfigurationByOwnerRequest
  ): Promise<GetPatternConfigurationByOwnerResponse>;
  GetEnabledPatternCount(
    ctx: T,
    request: GetEnabledPatternCountRequest
  ): Promise<GetEnabledPatternCountResponse>;
}

export enum PatternConfigurationsAPIMethod {
  UpsertPatternConfiguration = "UpsertPatternConfiguration",
  GetPatternConfigurationByOwner = "GetPatternConfigurationByOwner",
  GetEnabledPatternCount = "GetEnabledPatternCount",
}

export const PatternConfigurationsAPIMethodList = [
  PatternConfigurationsAPIMethod.UpsertPatternConfiguration,
  PatternConfigurationsAPIMethod.GetPatternConfigurationByOwner,
  PatternConfigurationsAPIMethod.GetEnabledPatternCount,
];

export function createPatternConfigurationsAPIServer<
  T extends TwirpContext = TwirpContext
>(service: PatternConfigurationsAPITwirp<T>) {
  return new TwirpServer<PatternConfigurationsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "PatternConfigurationsAPI",
    methodList: PatternConfigurationsAPIMethodList,
    matchRoute: matchPatternConfigurationsAPIRoute,
  });
}

function matchPatternConfigurationsAPIRoute<
  T extends TwirpContext = TwirpContext
>(method: string, events: RouterEvents<T>) {
  switch (method) {
    case "UpsertPatternConfiguration":
      return async (
        ctx: T,
        service: PatternConfigurationsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          UpsertPatternConfigurationRequest,
          UpsertPatternConfigurationResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "UpsertPatternConfiguration" };
        await events.onMatch(ctx);
        return handlePatternConfigurationsAPIUpsertPatternConfigurationRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetPatternConfigurationByOwner":
      return async (
        ctx: T,
        service: PatternConfigurationsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetPatternConfigurationByOwnerRequest,
          GetPatternConfigurationByOwnerResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetPatternConfigurationByOwner" };
        await events.onMatch(ctx);
        return handlePatternConfigurationsAPIGetPatternConfigurationByOwnerRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetEnabledPatternCount":
      return async (
        ctx: T,
        service: PatternConfigurationsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetEnabledPatternCountRequest,
          GetEnabledPatternCountResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetEnabledPatternCount" };
        await events.onMatch(ctx);
        return handlePatternConfigurationsAPIGetEnabledPatternCountRequest(
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

function handlePatternConfigurationsAPIUpsertPatternConfigurationRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpsertPatternConfigurationRequest,
    UpsertPatternConfigurationResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePatternConfigurationsAPIUpsertPatternConfigurationJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePatternConfigurationsAPIUpsertPatternConfigurationProtobuf<T>(
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

function handlePatternConfigurationsAPIGetPatternConfigurationByOwnerRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPatternConfigurationByOwnerRequest,
    GetPatternConfigurationByOwnerResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePatternConfigurationsAPIGetPatternConfigurationByOwnerJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePatternConfigurationsAPIGetPatternConfigurationByOwnerProtobuf<T>(
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

function handlePatternConfigurationsAPIGetEnabledPatternCountRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnabledPatternCountRequest,
    GetEnabledPatternCountResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePatternConfigurationsAPIGetEnabledPatternCountJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePatternConfigurationsAPIGetEnabledPatternCountProtobuf<T>(
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
async function handlePatternConfigurationsAPIUpsertPatternConfigurationJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpsertPatternConfigurationRequest,
    UpsertPatternConfigurationResponse
  >[]
) {
  let request: UpsertPatternConfigurationRequest;
  let response: UpsertPatternConfigurationResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = UpsertPatternConfigurationRequest.fromJson(body, {
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
      UpsertPatternConfigurationRequest,
      UpsertPatternConfigurationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpsertPatternConfiguration(ctx, inputReq);
    });
  } else {
    response = await service.UpsertPatternConfiguration(ctx, request!);
  }

  return JSON.stringify(
    UpsertPatternConfigurationResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handlePatternConfigurationsAPIGetPatternConfigurationByOwnerJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPatternConfigurationByOwnerRequest,
    GetPatternConfigurationByOwnerResponse
  >[]
) {
  let request: GetPatternConfigurationByOwnerRequest;
  let response: GetPatternConfigurationByOwnerResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetPatternConfigurationByOwnerRequest.fromJson(body, {
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
      GetPatternConfigurationByOwnerRequest,
      GetPatternConfigurationByOwnerResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPatternConfigurationByOwner(ctx, inputReq);
    });
  } else {
    response = await service.GetPatternConfigurationByOwner(ctx, request!);
  }

  return JSON.stringify(
    GetPatternConfigurationByOwnerResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handlePatternConfigurationsAPIGetEnabledPatternCountJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnabledPatternCountRequest,
    GetEnabledPatternCountResponse
  >[]
) {
  let request: GetEnabledPatternCountRequest;
  let response: GetEnabledPatternCountResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetEnabledPatternCountRequest.fromJson(body, {
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
      GetEnabledPatternCountRequest,
      GetEnabledPatternCountResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetEnabledPatternCount(ctx, inputReq);
    });
  } else {
    response = await service.GetEnabledPatternCount(ctx, request!);
  }

  return JSON.stringify(
    GetEnabledPatternCountResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handlePatternConfigurationsAPIUpsertPatternConfigurationProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpsertPatternConfigurationRequest,
    UpsertPatternConfigurationResponse
  >[]
) {
  let request: UpsertPatternConfigurationRequest;
  let response: UpsertPatternConfigurationResponse;

  try {
    request = UpsertPatternConfigurationRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UpsertPatternConfigurationRequest,
      UpsertPatternConfigurationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpsertPatternConfiguration(ctx, inputReq);
    });
  } else {
    response = await service.UpsertPatternConfiguration(ctx, request!);
  }

  return Buffer.from(UpsertPatternConfigurationResponse.toBinary(response));
}

async function handlePatternConfigurationsAPIGetPatternConfigurationByOwnerProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPatternConfigurationByOwnerRequest,
    GetPatternConfigurationByOwnerResponse
  >[]
) {
  let request: GetPatternConfigurationByOwnerRequest;
  let response: GetPatternConfigurationByOwnerResponse;

  try {
    request = GetPatternConfigurationByOwnerRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetPatternConfigurationByOwnerRequest,
      GetPatternConfigurationByOwnerResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPatternConfigurationByOwner(ctx, inputReq);
    });
  } else {
    response = await service.GetPatternConfigurationByOwner(ctx, request!);
  }

  return Buffer.from(GetPatternConfigurationByOwnerResponse.toBinary(response));
}

async function handlePatternConfigurationsAPIGetEnabledPatternCountProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PatternConfigurationsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnabledPatternCountRequest,
    GetEnabledPatternCountResponse
  >[]
) {
  let request: GetEnabledPatternCountRequest;
  let response: GetEnabledPatternCountResponse;

  try {
    request = GetEnabledPatternCountRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetEnabledPatternCountRequest,
      GetEnabledPatternCountResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetEnabledPatternCount(ctx, inputReq);
    });
  } else {
    response = await service.GetEnabledPatternCount(ctx, request!);
  }

  return Buffer.from(GetEnabledPatternCountResponse.toBinary(response));
}
