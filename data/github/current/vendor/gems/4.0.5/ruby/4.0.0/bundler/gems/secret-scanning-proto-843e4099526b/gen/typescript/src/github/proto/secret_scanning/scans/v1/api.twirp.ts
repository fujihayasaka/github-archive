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
  AddBypassRequest,
  AddBypassResponse,
  PromoteBypassRequest,
  PromoteBypassResponse,
  GetBypassPlaceholderRequest,
  GetBypassPlaceholderResponse,
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
  AddBypass(request: AddBypassRequest): Promise<AddBypassResponse>;
  PromoteBypass(request: PromoteBypassRequest): Promise<PromoteBypassResponse>;
  GetBypassPlaceholder(
    request: GetBypassPlaceholderRequest
  ): Promise<GetBypassPlaceholderResponse>;
}

export class ScansAPIClientJSON implements ScansAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.AddBypass.bind(this);
    this.PromoteBypass.bind(this);
    this.GetBypassPlaceholder.bind(this);
  }
  AddBypass(request: AddBypassRequest): Promise<AddBypassResponse> {
    const data = AddBypassRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v1.ScansAPI",
      "AddBypass",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      AddBypassResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  PromoteBypass(request: PromoteBypassRequest): Promise<PromoteBypassResponse> {
    const data = PromoteBypassRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v1.ScansAPI",
      "PromoteBypass",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      PromoteBypassResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetBypassPlaceholder(
    request: GetBypassPlaceholderRequest
  ): Promise<GetBypassPlaceholderResponse> {
    const data = GetBypassPlaceholderRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v1.ScansAPI",
      "GetBypassPlaceholder",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBypassPlaceholderResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class ScansAPIClientProtobuf implements ScansAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.AddBypass.bind(this);
    this.PromoteBypass.bind(this);
    this.GetBypassPlaceholder.bind(this);
  }
  AddBypass(request: AddBypassRequest): Promise<AddBypassResponse> {
    const data = AddBypassRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v1.ScansAPI",
      "AddBypass",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      AddBypassResponse.fromBinary(data as Uint8Array)
    );
  }

  PromoteBypass(request: PromoteBypassRequest): Promise<PromoteBypassResponse> {
    const data = PromoteBypassRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v1.ScansAPI",
      "PromoteBypass",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      PromoteBypassResponse.fromBinary(data as Uint8Array)
    );
  }

  GetBypassPlaceholder(
    request: GetBypassPlaceholderRequest
  ): Promise<GetBypassPlaceholderResponse> {
    const data = GetBypassPlaceholderRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v1.ScansAPI",
      "GetBypassPlaceholder",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBypassPlaceholderResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface ScansAPITwirp<T extends TwirpContext = TwirpContext> {
  AddBypass(ctx: T, request: AddBypassRequest): Promise<AddBypassResponse>;
  PromoteBypass(
    ctx: T,
    request: PromoteBypassRequest
  ): Promise<PromoteBypassResponse>;
  GetBypassPlaceholder(
    ctx: T,
    request: GetBypassPlaceholderRequest
  ): Promise<GetBypassPlaceholderResponse>;
}

export enum ScansAPIMethod {
  AddBypass = "AddBypass",
  PromoteBypass = "PromoteBypass",
  GetBypassPlaceholder = "GetBypassPlaceholder",
}

export const ScansAPIMethodList = [
  ScansAPIMethod.AddBypass,
  ScansAPIMethod.PromoteBypass,
  ScansAPIMethod.GetBypassPlaceholder,
];

export function createScansAPIServer<T extends TwirpContext = TwirpContext>(
  service: ScansAPITwirp<T>
) {
  return new TwirpServer<ScansAPITwirp, T>({
    service,
    packageName: "github.secretscanning.scans.v1",
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
    case "AddBypass":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, AddBypassRequest, AddBypassResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "AddBypass" };
        await events.onMatch(ctx);
        return handleScansAPIAddBypassRequest(ctx, service, data, interceptors);
      };
    case "PromoteBypass":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          PromoteBypassRequest,
          PromoteBypassResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "PromoteBypass" };
        await events.onMatch(ctx);
        return handleScansAPIPromoteBypassRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetBypassPlaceholder":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetBypassPlaceholderRequest,
          GetBypassPlaceholderResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetBypassPlaceholder" };
        await events.onMatch(ctx);
        return handleScansAPIGetBypassPlaceholderRequest(
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

function handleScansAPIAddBypassRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddBypassRequest, AddBypassResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIAddBypassJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleScansAPIAddBypassProtobuf<T>(
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

function handleScansAPIPromoteBypassRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, PromoteBypassRequest, PromoteBypassResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIPromoteBypassJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScansAPIPromoteBypassProtobuf<T>(
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

function handleScansAPIGetBypassPlaceholderRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassPlaceholderRequest,
    GetBypassPlaceholderResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIGetBypassPlaceholderJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScansAPIGetBypassPlaceholderProtobuf<T>(
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
async function handleScansAPIAddBypassJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddBypassRequest, AddBypassResponse>[]
) {
  let request: AddBypassRequest;
  let response: AddBypassResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = AddBypassRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      AddBypassRequest,
      AddBypassResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddBypass(ctx, inputReq);
    });
  } else {
    response = await service.AddBypass(ctx, request!);
  }

  return JSON.stringify(
    AddBypassResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIPromoteBypassJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, PromoteBypassRequest, PromoteBypassResponse>[]
) {
  let request: PromoteBypassRequest;
  let response: PromoteBypassResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = PromoteBypassRequest.fromJson(body, {
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
      PromoteBypassRequest,
      PromoteBypassResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.PromoteBypass(ctx, inputReq);
    });
  } else {
    response = await service.PromoteBypass(ctx, request!);
  }

  return JSON.stringify(
    PromoteBypassResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIGetBypassPlaceholderJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassPlaceholderRequest,
    GetBypassPlaceholderResponse
  >[]
) {
  let request: GetBypassPlaceholderRequest;
  let response: GetBypassPlaceholderResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBypassPlaceholderRequest.fromJson(body, {
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
      GetBypassPlaceholderRequest,
      GetBypassPlaceholderResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassPlaceholder(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassPlaceholder(ctx, request!);
  }

  return JSON.stringify(
    GetBypassPlaceholderResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleScansAPIAddBypassProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddBypassRequest, AddBypassResponse>[]
) {
  let request: AddBypassRequest;
  let response: AddBypassResponse;

  try {
    request = AddBypassRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      AddBypassRequest,
      AddBypassResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddBypass(ctx, inputReq);
    });
  } else {
    response = await service.AddBypass(ctx, request!);
  }

  return Buffer.from(AddBypassResponse.toBinary(response));
}

async function handleScansAPIPromoteBypassProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, PromoteBypassRequest, PromoteBypassResponse>[]
) {
  let request: PromoteBypassRequest;
  let response: PromoteBypassResponse;

  try {
    request = PromoteBypassRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      PromoteBypassRequest,
      PromoteBypassResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.PromoteBypass(ctx, inputReq);
    });
  } else {
    response = await service.PromoteBypass(ctx, request!);
  }

  return Buffer.from(PromoteBypassResponse.toBinary(response));
}

async function handleScansAPIGetBypassPlaceholderProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassPlaceholderRequest,
    GetBypassPlaceholderResponse
  >[]
) {
  let request: GetBypassPlaceholderRequest;
  let response: GetBypassPlaceholderResponse;

  try {
    request = GetBypassPlaceholderRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBypassPlaceholderRequest,
      GetBypassPlaceholderResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassPlaceholder(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassPlaceholder(ctx, request!);
  }

  return Buffer.from(GetBypassPlaceholderResponse.toBinary(response));
}
