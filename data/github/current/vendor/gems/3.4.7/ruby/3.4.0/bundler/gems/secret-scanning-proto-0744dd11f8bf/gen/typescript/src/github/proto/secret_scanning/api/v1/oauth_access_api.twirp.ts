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
  RevokeOauthAccessRequest,
  RevokeOauthAccessResponse,
  VerifyOauthAccessRequest,
  VerifyOauthAccessResponse,
} from "./oauth_access_api";

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

export interface OauthAccessAPIClient {
  RevokeOauthAccess(
    request: RevokeOauthAccessRequest
  ): Promise<RevokeOauthAccessResponse>;
  VerifyOauthAccess(
    request: VerifyOauthAccessRequest
  ): Promise<VerifyOauthAccessResponse>;
}

export class OauthAccessAPIClientJSON implements OauthAccessAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.RevokeOauthAccess.bind(this);
    this.VerifyOauthAccess.bind(this);
  }
  RevokeOauthAccess(
    request: RevokeOauthAccessRequest
  ): Promise<RevokeOauthAccessResponse> {
    const data = RevokeOauthAccessRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.OauthAccessAPI",
      "RevokeOauthAccess",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      RevokeOauthAccessResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  VerifyOauthAccess(
    request: VerifyOauthAccessRequest
  ): Promise<VerifyOauthAccessResponse> {
    const data = VerifyOauthAccessRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.OauthAccessAPI",
      "VerifyOauthAccess",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      VerifyOauthAccessResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class OauthAccessAPIClientProtobuf implements OauthAccessAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.RevokeOauthAccess.bind(this);
    this.VerifyOauthAccess.bind(this);
  }
  RevokeOauthAccess(
    request: RevokeOauthAccessRequest
  ): Promise<RevokeOauthAccessResponse> {
    const data = RevokeOauthAccessRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.OauthAccessAPI",
      "RevokeOauthAccess",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      RevokeOauthAccessResponse.fromBinary(data as Uint8Array)
    );
  }

  VerifyOauthAccess(
    request: VerifyOauthAccessRequest
  ): Promise<VerifyOauthAccessResponse> {
    const data = VerifyOauthAccessRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.OauthAccessAPI",
      "VerifyOauthAccess",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      VerifyOauthAccessResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface OauthAccessAPITwirp<T extends TwirpContext = TwirpContext> {
  RevokeOauthAccess(
    ctx: T,
    request: RevokeOauthAccessRequest
  ): Promise<RevokeOauthAccessResponse>;
  VerifyOauthAccess(
    ctx: T,
    request: VerifyOauthAccessRequest
  ): Promise<VerifyOauthAccessResponse>;
}

export enum OauthAccessAPIMethod {
  RevokeOauthAccess = "RevokeOauthAccess",
  VerifyOauthAccess = "VerifyOauthAccess",
}

export const OauthAccessAPIMethodList = [
  OauthAccessAPIMethod.RevokeOauthAccess,
  OauthAccessAPIMethod.VerifyOauthAccess,
];

export function createOauthAccessAPIServer<
  T extends TwirpContext = TwirpContext
>(service: OauthAccessAPITwirp<T>) {
  return new TwirpServer<OauthAccessAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "OauthAccessAPI",
    methodList: OauthAccessAPIMethodList,
    matchRoute: matchOauthAccessAPIRoute,
  });
}

function matchOauthAccessAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "RevokeOauthAccess":
      return async (
        ctx: T,
        service: OauthAccessAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          RevokeOauthAccessRequest,
          RevokeOauthAccessResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "RevokeOauthAccess" };
        await events.onMatch(ctx);
        return handleOauthAccessAPIRevokeOauthAccessRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "VerifyOauthAccess":
      return async (
        ctx: T,
        service: OauthAccessAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          VerifyOauthAccessRequest,
          VerifyOauthAccessResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "VerifyOauthAccess" };
        await events.onMatch(ctx);
        return handleOauthAccessAPIVerifyOauthAccessRequest(
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

function handleOauthAccessAPIRevokeOauthAccessRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OauthAccessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    RevokeOauthAccessRequest,
    RevokeOauthAccessResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleOauthAccessAPIRevokeOauthAccessJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleOauthAccessAPIRevokeOauthAccessProtobuf<T>(
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

function handleOauthAccessAPIVerifyOauthAccessRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OauthAccessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyOauthAccessRequest,
    VerifyOauthAccessResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleOauthAccessAPIVerifyOauthAccessJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleOauthAccessAPIVerifyOauthAccessProtobuf<T>(
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
async function handleOauthAccessAPIRevokeOauthAccessJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OauthAccessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    RevokeOauthAccessRequest,
    RevokeOauthAccessResponse
  >[]
) {
  let request: RevokeOauthAccessRequest;
  let response: RevokeOauthAccessResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = RevokeOauthAccessRequest.fromJson(body, {
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
      RevokeOauthAccessRequest,
      RevokeOauthAccessResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RevokeOauthAccess(ctx, inputReq);
    });
  } else {
    response = await service.RevokeOauthAccess(ctx, request!);
  }

  return JSON.stringify(
    RevokeOauthAccessResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleOauthAccessAPIVerifyOauthAccessJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OauthAccessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyOauthAccessRequest,
    VerifyOauthAccessResponse
  >[]
) {
  let request: VerifyOauthAccessRequest;
  let response: VerifyOauthAccessResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = VerifyOauthAccessRequest.fromJson(body, {
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
      VerifyOauthAccessRequest,
      VerifyOauthAccessResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifyOauthAccess(ctx, inputReq);
    });
  } else {
    response = await service.VerifyOauthAccess(ctx, request!);
  }

  return JSON.stringify(
    VerifyOauthAccessResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleOauthAccessAPIRevokeOauthAccessProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OauthAccessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    RevokeOauthAccessRequest,
    RevokeOauthAccessResponse
  >[]
) {
  let request: RevokeOauthAccessRequest;
  let response: RevokeOauthAccessResponse;

  try {
    request = RevokeOauthAccessRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      RevokeOauthAccessRequest,
      RevokeOauthAccessResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RevokeOauthAccess(ctx, inputReq);
    });
  } else {
    response = await service.RevokeOauthAccess(ctx, request!);
  }

  return Buffer.from(RevokeOauthAccessResponse.toBinary(response));
}

async function handleOauthAccessAPIVerifyOauthAccessProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OauthAccessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyOauthAccessRequest,
    VerifyOauthAccessResponse
  >[]
) {
  let request: VerifyOauthAccessRequest;
  let response: VerifyOauthAccessResponse;

  try {
    request = VerifyOauthAccessRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      VerifyOauthAccessRequest,
      VerifyOauthAccessResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifyOauthAccess(ctx, inputReq);
    });
  } else {
    response = await service.VerifyOauthAccess(ctx, request!);
  }

  return Buffer.from(VerifyOauthAccessResponse.toBinary(response));
}
