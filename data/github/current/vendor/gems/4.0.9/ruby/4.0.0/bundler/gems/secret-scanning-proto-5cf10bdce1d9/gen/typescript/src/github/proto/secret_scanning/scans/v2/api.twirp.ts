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
  ScanPushRequest,
  ScanPushResponse,
  ScanBytesRequest,
  ScanBytesResponse,
  ScanFilesRequest,
  ScanFilesResponse,
} from "./api";

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

export interface ScansAPIClient {
  ScanPush(request: ScanPushRequest): Promise<ScanPushResponse>;
  ScanBytes(request: ScanBytesRequest): Promise<ScanBytesResponse>;
  ScanFiles(request: ScanFilesRequest): Promise<ScanFilesResponse>;
}

export class ScansAPIClientJSON implements ScansAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ScanPush.bind(this);
    this.ScanBytes.bind(this);
    this.ScanFiles.bind(this);
  }
  ScanPush(request: ScanPushRequest): Promise<ScanPushResponse> {
    const data = ScanPushRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "ScanPush",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ScanPushResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  ScanBytes(request: ScanBytesRequest): Promise<ScanBytesResponse> {
    const data = ScanBytesRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "ScanBytes",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ScanBytesResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  ScanFiles(request: ScanFilesRequest): Promise<ScanFilesResponse> {
    const data = ScanFilesRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "ScanFiles",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ScanFilesResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class ScansAPIClientProtobuf implements ScansAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ScanPush.bind(this);
    this.ScanBytes.bind(this);
    this.ScanFiles.bind(this);
  }
  ScanPush(request: ScanPushRequest): Promise<ScanPushResponse> {
    const data = ScanPushRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "ScanPush",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ScanPushResponse.fromBinary(data as Uint8Array)
    );
  }

  ScanBytes(request: ScanBytesRequest): Promise<ScanBytesResponse> {
    const data = ScanBytesRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "ScanBytes",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ScanBytesResponse.fromBinary(data as Uint8Array)
    );
  }

  ScanFiles(request: ScanFilesRequest): Promise<ScanFilesResponse> {
    const data = ScanFilesRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "ScanFiles",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ScanFilesResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface ScansAPITwirp<T extends TwirpContext = TwirpContext> {
  ScanPush(ctx: T, request: ScanPushRequest): Promise<ScanPushResponse>;
  ScanBytes(ctx: T, request: ScanBytesRequest): Promise<ScanBytesResponse>;
  ScanFiles(ctx: T, request: ScanFilesRequest): Promise<ScanFilesResponse>;
}

export enum ScansAPIMethod {
  ScanPush = "ScanPush",
  ScanBytes = "ScanBytes",
  ScanFiles = "ScanFiles",
}

export const ScansAPIMethodList = [
  ScansAPIMethod.ScanPush,
  ScansAPIMethod.ScanBytes,
  ScansAPIMethod.ScanFiles,
];

export function createScansAPIServer<T extends TwirpContext = TwirpContext>(
  service: ScansAPITwirp<T>
) {
  return new TwirpServer<ScansAPITwirp, T>({
    service,
    packageName: "github.secretscanning.scans.v2",
    serviceName: "ScansAPI",
    methodList: ScansAPIMethodList,
    matchRoute: matchScansAPIRoute,
  });
}

function matchScansAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "ScanPush":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, ScanPushRequest, ScanPushResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "ScanPush" };
        await events.onMatch(ctx);
        return handleScansAPIScanPushRequest(ctx, service, data, interceptors);
      };
    case "ScanBytes":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, ScanBytesRequest, ScanBytesResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "ScanBytes" };
        await events.onMatch(ctx);
        return handleScansAPIScanBytesRequest(ctx, service, data, interceptors);
      };
    case "ScanFiles":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, ScanFilesRequest, ScanFilesResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "ScanFiles" };
        await events.onMatch(ctx);
        return handleScansAPIScanFilesRequest(ctx, service, data, interceptors);
      };
    default:
      events.onNotFound();
      const msg = `no handler found`;
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleScansAPIScanPushRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanPushRequest, ScanPushResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIScanPushJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleScansAPIScanPushProtobuf<T>(
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

function handleScansAPIScanBytesRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanBytesRequest, ScanBytesResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIScanBytesJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleScansAPIScanBytesProtobuf<T>(
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

function handleScansAPIScanFilesRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanFilesRequest, ScanFilesResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIScanFilesJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleScansAPIScanFilesProtobuf<T>(
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
async function handleScansAPIScanPushJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanPushRequest, ScanPushResponse>[]
) {
  let request: ScanPushRequest;
  let response: ScanPushResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ScanPushRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ScanPushRequest,
      ScanPushResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ScanPush(ctx, inputReq);
    });
  } else {
    response = await service.ScanPush(ctx, request!);
  }

  return JSON.stringify(
    ScanPushResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIScanBytesJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanBytesRequest, ScanBytesResponse>[]
) {
  let request: ScanBytesRequest;
  let response: ScanBytesResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ScanBytesRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ScanBytesRequest,
      ScanBytesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ScanBytes(ctx, inputReq);
    });
  } else {
    response = await service.ScanBytes(ctx, request!);
  }

  return JSON.stringify(
    ScanBytesResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIScanFilesJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanFilesRequest, ScanFilesResponse>[]
) {
  let request: ScanFilesRequest;
  let response: ScanFilesResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ScanFilesRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ScanFilesRequest,
      ScanFilesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ScanFiles(ctx, inputReq);
    });
  } else {
    response = await service.ScanFiles(ctx, request!);
  }

  return JSON.stringify(
    ScanFilesResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleScansAPIScanPushProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanPushRequest, ScanPushResponse>[]
) {
  let request: ScanPushRequest;
  let response: ScanPushResponse;

  try {
    request = ScanPushRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ScanPushRequest,
      ScanPushResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ScanPush(ctx, inputReq);
    });
  } else {
    response = await service.ScanPush(ctx, request!);
  }

  return Buffer.from(ScanPushResponse.toBinary(response));
}

async function handleScansAPIScanBytesProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanBytesRequest, ScanBytesResponse>[]
) {
  let request: ScanBytesRequest;
  let response: ScanBytesResponse;

  try {
    request = ScanBytesRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ScanBytesRequest,
      ScanBytesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ScanBytes(ctx, inputReq);
    });
  } else {
    response = await service.ScanBytes(ctx, request!);
  }

  return Buffer.from(ScanBytesResponse.toBinary(response));
}

async function handleScansAPIScanFilesProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ScanFilesRequest, ScanFilesResponse>[]
) {
  let request: ScanFilesRequest;
  let response: ScanFilesResponse;

  try {
    request = ScanFilesRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ScanFilesRequest,
      ScanFilesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ScanFiles(ctx, inputReq);
    });
  } else {
    response = await service.ScanFiles(ctx, request!);
  }

  return Buffer.from(ScanFilesResponse.toBinary(response));
}
