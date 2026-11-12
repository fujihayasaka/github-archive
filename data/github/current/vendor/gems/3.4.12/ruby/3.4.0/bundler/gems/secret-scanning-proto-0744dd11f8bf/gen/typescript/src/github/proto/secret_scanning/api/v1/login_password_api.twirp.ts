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
  RevokeLoginPasswordRequest,
  RevokeLoginPasswordResponse,
  VerifyLoginPasswordRequest,
  VerifyLoginPasswordResponse,
} from "./login_password_api";

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

export interface LoginPasswordAPIClient {
  RevokeLoginPassword(
    request: RevokeLoginPasswordRequest
  ): Promise<RevokeLoginPasswordResponse>;
  VerifyLoginPassword(
    request: VerifyLoginPasswordRequest
  ): Promise<VerifyLoginPasswordResponse>;
}

export class LoginPasswordAPIClientJSON implements LoginPasswordAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.RevokeLoginPassword.bind(this);
    this.VerifyLoginPassword.bind(this);
  }
  RevokeLoginPassword(
    request: RevokeLoginPasswordRequest
  ): Promise<RevokeLoginPasswordResponse> {
    const data = RevokeLoginPasswordRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.LoginPasswordAPI",
      "RevokeLoginPassword",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      RevokeLoginPasswordResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  VerifyLoginPassword(
    request: VerifyLoginPasswordRequest
  ): Promise<VerifyLoginPasswordResponse> {
    const data = VerifyLoginPasswordRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.LoginPasswordAPI",
      "VerifyLoginPassword",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      VerifyLoginPasswordResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class LoginPasswordAPIClientProtobuf implements LoginPasswordAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.RevokeLoginPassword.bind(this);
    this.VerifyLoginPassword.bind(this);
  }
  RevokeLoginPassword(
    request: RevokeLoginPasswordRequest
  ): Promise<RevokeLoginPasswordResponse> {
    const data = RevokeLoginPasswordRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.LoginPasswordAPI",
      "RevokeLoginPassword",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      RevokeLoginPasswordResponse.fromBinary(data as Uint8Array)
    );
  }

  VerifyLoginPassword(
    request: VerifyLoginPasswordRequest
  ): Promise<VerifyLoginPasswordResponse> {
    const data = VerifyLoginPasswordRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.LoginPasswordAPI",
      "VerifyLoginPassword",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      VerifyLoginPasswordResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface LoginPasswordAPITwirp<T extends TwirpContext = TwirpContext> {
  RevokeLoginPassword(
    ctx: T,
    request: RevokeLoginPasswordRequest
  ): Promise<RevokeLoginPasswordResponse>;
  VerifyLoginPassword(
    ctx: T,
    request: VerifyLoginPasswordRequest
  ): Promise<VerifyLoginPasswordResponse>;
}

export enum LoginPasswordAPIMethod {
  RevokeLoginPassword = "RevokeLoginPassword",
  VerifyLoginPassword = "VerifyLoginPassword",
}

export const LoginPasswordAPIMethodList = [
  LoginPasswordAPIMethod.RevokeLoginPassword,
  LoginPasswordAPIMethod.VerifyLoginPassword,
];

export function createLoginPasswordAPIServer<
  T extends TwirpContext = TwirpContext
>(service: LoginPasswordAPITwirp<T>) {
  return new TwirpServer<LoginPasswordAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "LoginPasswordAPI",
    methodList: LoginPasswordAPIMethodList,
    matchRoute: matchLoginPasswordAPIRoute,
  });
}

function matchLoginPasswordAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "RevokeLoginPassword":
      return async (
        ctx: T,
        service: LoginPasswordAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          RevokeLoginPasswordRequest,
          RevokeLoginPasswordResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "RevokeLoginPassword" };
        await events.onMatch(ctx);
        return handleLoginPasswordAPIRevokeLoginPasswordRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "VerifyLoginPassword":
      return async (
        ctx: T,
        service: LoginPasswordAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          VerifyLoginPasswordRequest,
          VerifyLoginPasswordResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "VerifyLoginPassword" };
        await events.onMatch(ctx);
        return handleLoginPasswordAPIVerifyLoginPasswordRequest(
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

function handleLoginPasswordAPIRevokeLoginPasswordRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: LoginPasswordAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    RevokeLoginPasswordRequest,
    RevokeLoginPasswordResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleLoginPasswordAPIRevokeLoginPasswordJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleLoginPasswordAPIRevokeLoginPasswordProtobuf<T>(
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

function handleLoginPasswordAPIVerifyLoginPasswordRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: LoginPasswordAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyLoginPasswordRequest,
    VerifyLoginPasswordResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleLoginPasswordAPIVerifyLoginPasswordJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleLoginPasswordAPIVerifyLoginPasswordProtobuf<T>(
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
async function handleLoginPasswordAPIRevokeLoginPasswordJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: LoginPasswordAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    RevokeLoginPasswordRequest,
    RevokeLoginPasswordResponse
  >[]
) {
  let request: RevokeLoginPasswordRequest;
  let response: RevokeLoginPasswordResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = RevokeLoginPasswordRequest.fromJson(body, {
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
      RevokeLoginPasswordRequest,
      RevokeLoginPasswordResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RevokeLoginPassword(ctx, inputReq);
    });
  } else {
    response = await service.RevokeLoginPassword(ctx, request!);
  }

  return JSON.stringify(
    RevokeLoginPasswordResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleLoginPasswordAPIVerifyLoginPasswordJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: LoginPasswordAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyLoginPasswordRequest,
    VerifyLoginPasswordResponse
  >[]
) {
  let request: VerifyLoginPasswordRequest;
  let response: VerifyLoginPasswordResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = VerifyLoginPasswordRequest.fromJson(body, {
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
      VerifyLoginPasswordRequest,
      VerifyLoginPasswordResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifyLoginPassword(ctx, inputReq);
    });
  } else {
    response = await service.VerifyLoginPassword(ctx, request!);
  }

  return JSON.stringify(
    VerifyLoginPasswordResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleLoginPasswordAPIRevokeLoginPasswordProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: LoginPasswordAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    RevokeLoginPasswordRequest,
    RevokeLoginPasswordResponse
  >[]
) {
  let request: RevokeLoginPasswordRequest;
  let response: RevokeLoginPasswordResponse;

  try {
    request = RevokeLoginPasswordRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      RevokeLoginPasswordRequest,
      RevokeLoginPasswordResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RevokeLoginPassword(ctx, inputReq);
    });
  } else {
    response = await service.RevokeLoginPassword(ctx, request!);
  }

  return Buffer.from(RevokeLoginPasswordResponse.toBinary(response));
}

async function handleLoginPasswordAPIVerifyLoginPasswordProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: LoginPasswordAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyLoginPasswordRequest,
    VerifyLoginPasswordResponse
  >[]
) {
  let request: VerifyLoginPasswordRequest;
  let response: VerifyLoginPasswordResponse;

  try {
    request = VerifyLoginPasswordRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      VerifyLoginPasswordRequest,
      VerifyLoginPasswordResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifyLoginPassword(ctx, inputReq);
    });
  } else {
    response = await service.VerifyLoginPassword(ctx, request!);
  }

  return Buffer.from(VerifyLoginPasswordResponse.toBinary(response));
}
