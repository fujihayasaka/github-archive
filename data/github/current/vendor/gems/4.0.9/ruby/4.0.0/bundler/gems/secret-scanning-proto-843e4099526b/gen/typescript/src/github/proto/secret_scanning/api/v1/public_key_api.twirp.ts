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
  UnverifyPublicKeyRequest,
  UnverifyPublicKeyResponse,
  VerifyPrivateKeyRequest,
  VerifyPrivateKeyResponse,
} from "./public_key_api";

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

export interface PublicKeyAPIClient {
  UnverifyPublicKey(
    request: UnverifyPublicKeyRequest
  ): Promise<UnverifyPublicKeyResponse>;
  VerifyPrivateKey(
    request: VerifyPrivateKeyRequest
  ): Promise<VerifyPrivateKeyResponse>;
}

export class PublicKeyAPIClientJSON implements PublicKeyAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.UnverifyPublicKey.bind(this);
    this.VerifyPrivateKey.bind(this);
  }
  UnverifyPublicKey(
    request: UnverifyPublicKeyRequest
  ): Promise<UnverifyPublicKeyResponse> {
    const data = UnverifyPublicKeyRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.PublicKeyAPI",
      "UnverifyPublicKey",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      UnverifyPublicKeyResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  VerifyPrivateKey(
    request: VerifyPrivateKeyRequest
  ): Promise<VerifyPrivateKeyResponse> {
    const data = VerifyPrivateKeyRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.PublicKeyAPI",
      "VerifyPrivateKey",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      VerifyPrivateKeyResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class PublicKeyAPIClientProtobuf implements PublicKeyAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.UnverifyPublicKey.bind(this);
    this.VerifyPrivateKey.bind(this);
  }
  UnverifyPublicKey(
    request: UnverifyPublicKeyRequest
  ): Promise<UnverifyPublicKeyResponse> {
    const data = UnverifyPublicKeyRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.PublicKeyAPI",
      "UnverifyPublicKey",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      UnverifyPublicKeyResponse.fromBinary(data as Uint8Array)
    );
  }

  VerifyPrivateKey(
    request: VerifyPrivateKeyRequest
  ): Promise<VerifyPrivateKeyResponse> {
    const data = VerifyPrivateKeyRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.PublicKeyAPI",
      "VerifyPrivateKey",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      VerifyPrivateKeyResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface PublicKeyAPITwirp<T extends TwirpContext = TwirpContext> {
  UnverifyPublicKey(
    ctx: T,
    request: UnverifyPublicKeyRequest
  ): Promise<UnverifyPublicKeyResponse>;
  VerifyPrivateKey(
    ctx: T,
    request: VerifyPrivateKeyRequest
  ): Promise<VerifyPrivateKeyResponse>;
}

export enum PublicKeyAPIMethod {
  UnverifyPublicKey = "UnverifyPublicKey",
  VerifyPrivateKey = "VerifyPrivateKey",
}

export const PublicKeyAPIMethodList = [
  PublicKeyAPIMethod.UnverifyPublicKey,
  PublicKeyAPIMethod.VerifyPrivateKey,
];

export function createPublicKeyAPIServer<T extends TwirpContext = TwirpContext>(
  service: PublicKeyAPITwirp<T>
) {
  return new TwirpServer<PublicKeyAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "PublicKeyAPI",
    methodList: PublicKeyAPIMethodList,
    matchRoute: matchPublicKeyAPIRoute,
  });
}

function matchPublicKeyAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "UnverifyPublicKey":
      return async (
        ctx: T,
        service: PublicKeyAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          UnverifyPublicKeyRequest,
          UnverifyPublicKeyResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "UnverifyPublicKey" };
        await events.onMatch(ctx);
        return handlePublicKeyAPIUnverifyPublicKeyRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "VerifyPrivateKey":
      return async (
        ctx: T,
        service: PublicKeyAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          VerifyPrivateKeyRequest,
          VerifyPrivateKeyResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "VerifyPrivateKey" };
        await events.onMatch(ctx);
        return handlePublicKeyAPIVerifyPrivateKeyRequest(
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

function handlePublicKeyAPIUnverifyPublicKeyRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicKeyAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UnverifyPublicKeyRequest,
    UnverifyPublicKeyResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePublicKeyAPIUnverifyPublicKeyJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePublicKeyAPIUnverifyPublicKeyProtobuf<T>(
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

function handlePublicKeyAPIVerifyPrivateKeyRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicKeyAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyPrivateKeyRequest,
    VerifyPrivateKeyResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePublicKeyAPIVerifyPrivateKeyJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePublicKeyAPIVerifyPrivateKeyProtobuf<T>(
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
async function handlePublicKeyAPIUnverifyPublicKeyJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicKeyAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UnverifyPublicKeyRequest,
    UnverifyPublicKeyResponse
  >[]
) {
  let request: UnverifyPublicKeyRequest;
  let response: UnverifyPublicKeyResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = UnverifyPublicKeyRequest.fromJson(body, {
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
      UnverifyPublicKeyRequest,
      UnverifyPublicKeyResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UnverifyPublicKey(ctx, inputReq);
    });
  } else {
    response = await service.UnverifyPublicKey(ctx, request!);
  }

  return JSON.stringify(
    UnverifyPublicKeyResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handlePublicKeyAPIVerifyPrivateKeyJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicKeyAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyPrivateKeyRequest,
    VerifyPrivateKeyResponse
  >[]
) {
  let request: VerifyPrivateKeyRequest;
  let response: VerifyPrivateKeyResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = VerifyPrivateKeyRequest.fromJson(body, {
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
      VerifyPrivateKeyRequest,
      VerifyPrivateKeyResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifyPrivateKey(ctx, inputReq);
    });
  } else {
    response = await service.VerifyPrivateKey(ctx, request!);
  }

  return JSON.stringify(
    VerifyPrivateKeyResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handlePublicKeyAPIUnverifyPublicKeyProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicKeyAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UnverifyPublicKeyRequest,
    UnverifyPublicKeyResponse
  >[]
) {
  let request: UnverifyPublicKeyRequest;
  let response: UnverifyPublicKeyResponse;

  try {
    request = UnverifyPublicKeyRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UnverifyPublicKeyRequest,
      UnverifyPublicKeyResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UnverifyPublicKey(ctx, inputReq);
    });
  } else {
    response = await service.UnverifyPublicKey(ctx, request!);
  }

  return Buffer.from(UnverifyPublicKeyResponse.toBinary(response));
}

async function handlePublicKeyAPIVerifyPrivateKeyProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicKeyAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    VerifyPrivateKeyRequest,
    VerifyPrivateKeyResponse
  >[]
) {
  let request: VerifyPrivateKeyRequest;
  let response: VerifyPrivateKeyResponse;

  try {
    request = VerifyPrivateKeyRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      VerifyPrivateKeyRequest,
      VerifyPrivateKeyResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifyPrivateKey(ctx, inputReq);
    });
  } else {
    response = await service.VerifyPrivateKey(ctx, request!);
  }

  return Buffer.from(VerifyPrivateKeyResponse.toBinary(response));
}
