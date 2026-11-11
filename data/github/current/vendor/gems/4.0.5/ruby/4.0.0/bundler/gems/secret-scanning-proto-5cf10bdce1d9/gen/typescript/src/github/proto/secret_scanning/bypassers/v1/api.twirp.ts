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
  AddBypasserRequest,
  AddBypasserResponse,
  RemoveBypasserRequest,
  RemoveBypassersForSourceRequest,
  UpdateBypassersForSourceRequest,
  UpdateBypassersForSourceResponse,
  GetBypassersRequest,
  GetBypassersResponse,
} from "./api";
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

export interface BypasserAPIClient {
  AddBypasser(request: AddBypasserRequest): Promise<AddBypasserResponse>;
  RemoveBypasser(request: RemoveBypasserRequest): Promise<Empty>;
  RemoveBypassersForSource(
    request: RemoveBypassersForSourceRequest
  ): Promise<Empty>;
  UpdateBypassersForSource(
    request: UpdateBypassersForSourceRequest
  ): Promise<UpdateBypassersForSourceResponse>;
  GetBypassers(request: GetBypassersRequest): Promise<GetBypassersResponse>;
}

export class BypasserAPIClientJSON implements BypasserAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.AddBypasser.bind(this);
    this.RemoveBypasser.bind(this);
    this.RemoveBypassersForSource.bind(this);
    this.UpdateBypassersForSource.bind(this);
    this.GetBypassers.bind(this);
  }
  AddBypasser(request: AddBypasserRequest): Promise<AddBypasserResponse> {
    const data = AddBypasserRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "AddBypasser",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      AddBypasserResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  RemoveBypasser(request: RemoveBypasserRequest): Promise<Empty> {
    const data = RemoveBypasserRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "RemoveBypasser",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  RemoveBypassersForSource(
    request: RemoveBypassersForSourceRequest
  ): Promise<Empty> {
    const data = RemoveBypassersForSourceRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "RemoveBypassersForSource",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  UpdateBypassersForSource(
    request: UpdateBypassersForSourceRequest
  ): Promise<UpdateBypassersForSourceResponse> {
    const data = UpdateBypassersForSourceRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "UpdateBypassersForSource",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      UpdateBypassersForSourceResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetBypassers(request: GetBypassersRequest): Promise<GetBypassersResponse> {
    const data = GetBypassersRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "GetBypassers",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBypassersResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class BypasserAPIClientProtobuf implements BypasserAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.AddBypasser.bind(this);
    this.RemoveBypasser.bind(this);
    this.RemoveBypassersForSource.bind(this);
    this.UpdateBypassersForSource.bind(this);
    this.GetBypassers.bind(this);
  }
  AddBypasser(request: AddBypasserRequest): Promise<AddBypasserResponse> {
    const data = AddBypasserRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "AddBypasser",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      AddBypasserResponse.fromBinary(data as Uint8Array)
    );
  }

  RemoveBypasser(request: RemoveBypasserRequest): Promise<Empty> {
    const data = RemoveBypasserRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "RemoveBypasser",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  RemoveBypassersForSource(
    request: RemoveBypassersForSourceRequest
  ): Promise<Empty> {
    const data = RemoveBypassersForSourceRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "RemoveBypassersForSource",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  UpdateBypassersForSource(
    request: UpdateBypassersForSourceRequest
  ): Promise<UpdateBypassersForSourceResponse> {
    const data = UpdateBypassersForSourceRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "UpdateBypassersForSource",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      UpdateBypassersForSourceResponse.fromBinary(data as Uint8Array)
    );
  }

  GetBypassers(request: GetBypassersRequest): Promise<GetBypassersResponse> {
    const data = GetBypassersRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.bypassers.v1.BypasserAPI",
      "GetBypassers",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBypassersResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface BypasserAPITwirp<T extends TwirpContext = TwirpContext> {
  AddBypasser(
    ctx: T,
    request: AddBypasserRequest
  ): Promise<AddBypasserResponse>;
  RemoveBypasser(ctx: T, request: RemoveBypasserRequest): Promise<Empty>;
  RemoveBypassersForSource(
    ctx: T,
    request: RemoveBypassersForSourceRequest
  ): Promise<Empty>;
  UpdateBypassersForSource(
    ctx: T,
    request: UpdateBypassersForSourceRequest
  ): Promise<UpdateBypassersForSourceResponse>;
  GetBypassers(
    ctx: T,
    request: GetBypassersRequest
  ): Promise<GetBypassersResponse>;
}

export enum BypasserAPIMethod {
  AddBypasser = "AddBypasser",
  RemoveBypasser = "RemoveBypasser",
  RemoveBypassersForSource = "RemoveBypassersForSource",
  UpdateBypassersForSource = "UpdateBypassersForSource",
  GetBypassers = "GetBypassers",
}

export const BypasserAPIMethodList = [
  BypasserAPIMethod.AddBypasser,
  BypasserAPIMethod.RemoveBypasser,
  BypasserAPIMethod.RemoveBypassersForSource,
  BypasserAPIMethod.UpdateBypassersForSource,
  BypasserAPIMethod.GetBypassers,
];

export function createBypasserAPIServer<T extends TwirpContext = TwirpContext>(
  service: BypasserAPITwirp<T>
) {
  return new TwirpServer<BypasserAPITwirp, T>({
    service,
    packageName: "github.secretscanning.bypassers.v1",
    serviceName: "BypasserAPI",
    methodList: BypasserAPIMethodList,
    matchRoute: matchBypasserAPIRoute,
  });
}

function matchBypasserAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "AddBypasser":
      return async (
        ctx: T,
        service: BypasserAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, AddBypasserRequest, AddBypasserResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "AddBypasser" };
        await events.onMatch(ctx);
        return handleBypasserAPIAddBypasserRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "RemoveBypasser":
      return async (
        ctx: T,
        service: BypasserAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, RemoveBypasserRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "RemoveBypasser" };
        await events.onMatch(ctx);
        return handleBypasserAPIRemoveBypasserRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "RemoveBypassersForSource":
      return async (
        ctx: T,
        service: BypasserAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, RemoveBypassersForSourceRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "RemoveBypassersForSource" };
        await events.onMatch(ctx);
        return handleBypasserAPIRemoveBypassersForSourceRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "UpdateBypassersForSource":
      return async (
        ctx: T,
        service: BypasserAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          UpdateBypassersForSourceRequest,
          UpdateBypassersForSourceResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "UpdateBypassersForSource" };
        await events.onMatch(ctx);
        return handleBypasserAPIUpdateBypassersForSourceRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetBypassers":
      return async (
        ctx: T,
        service: BypasserAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetBypassersRequest,
          GetBypassersResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetBypassers" };
        await events.onMatch(ctx);
        return handleBypasserAPIGetBypassersRequest(
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

function handleBypasserAPIAddBypasserRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddBypasserRequest, AddBypasserResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleBypasserAPIAddBypasserJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleBypasserAPIAddBypasserProtobuf<T>(
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

function handleBypasserAPIRemoveBypasserRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypasserRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleBypasserAPIRemoveBypasserJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleBypasserAPIRemoveBypasserProtobuf<T>(
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

function handleBypasserAPIRemoveBypassersForSourceRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassersForSourceRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleBypasserAPIRemoveBypassersForSourceJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleBypasserAPIRemoveBypassersForSourceProtobuf<T>(
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

function handleBypasserAPIUpdateBypassersForSourceRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateBypassersForSourceRequest,
    UpdateBypassersForSourceResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleBypasserAPIUpdateBypassersForSourceJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleBypasserAPIUpdateBypassersForSourceProtobuf<T>(
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

function handleBypasserAPIGetBypassersRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetBypassersRequest, GetBypassersResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleBypasserAPIGetBypassersJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleBypasserAPIGetBypassersProtobuf<T>(
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
async function handleBypasserAPIAddBypasserJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddBypasserRequest, AddBypasserResponse>[]
) {
  let request: AddBypasserRequest;
  let response: AddBypasserResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = AddBypasserRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      AddBypasserRequest,
      AddBypasserResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddBypasser(ctx, inputReq);
    });
  } else {
    response = await service.AddBypasser(ctx, request!);
  }

  return JSON.stringify(
    AddBypasserResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleBypasserAPIRemoveBypasserJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypasserRequest, Empty>[]
) {
  let request: RemoveBypasserRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = RemoveBypasserRequest.fromJson(body, {
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
      RemoveBypasserRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypasser(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypasser(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleBypasserAPIRemoveBypassersForSourceJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassersForSourceRequest, Empty>[]
) {
  let request: RemoveBypassersForSourceRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = RemoveBypassersForSourceRequest.fromJson(body, {
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
      RemoveBypassersForSourceRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypassersForSource(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypassersForSource(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleBypasserAPIUpdateBypassersForSourceJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateBypassersForSourceRequest,
    UpdateBypassersForSourceResponse
  >[]
) {
  let request: UpdateBypassersForSourceRequest;
  let response: UpdateBypassersForSourceResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = UpdateBypassersForSourceRequest.fromJson(body, {
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
      UpdateBypassersForSourceRequest,
      UpdateBypassersForSourceResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateBypassersForSource(ctx, inputReq);
    });
  } else {
    response = await service.UpdateBypassersForSource(ctx, request!);
  }

  return JSON.stringify(
    UpdateBypassersForSourceResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleBypasserAPIGetBypassersJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetBypassersRequest, GetBypassersResponse>[]
) {
  let request: GetBypassersRequest;
  let response: GetBypassersResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBypassersRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBypassersRequest,
      GetBypassersResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassers(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassers(ctx, request!);
  }

  return JSON.stringify(
    GetBypassersResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleBypasserAPIAddBypasserProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, AddBypasserRequest, AddBypasserResponse>[]
) {
  let request: AddBypasserRequest;
  let response: AddBypasserResponse;

  try {
    request = AddBypasserRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      AddBypasserRequest,
      AddBypasserResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddBypasser(ctx, inputReq);
    });
  } else {
    response = await service.AddBypasser(ctx, request!);
  }

  return Buffer.from(AddBypasserResponse.toBinary(response));
}

async function handleBypasserAPIRemoveBypasserProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypasserRequest, Empty>[]
) {
  let request: RemoveBypasserRequest;
  let response: Empty;

  try {
    request = RemoveBypasserRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      RemoveBypasserRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypasser(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypasser(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleBypasserAPIRemoveBypassersForSourceProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassersForSourceRequest, Empty>[]
) {
  let request: RemoveBypassersForSourceRequest;
  let response: Empty;

  try {
    request = RemoveBypassersForSourceRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      RemoveBypassersForSourceRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypassersForSource(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypassersForSource(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleBypasserAPIUpdateBypassersForSourceProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateBypassersForSourceRequest,
    UpdateBypassersForSourceResponse
  >[]
) {
  let request: UpdateBypassersForSourceRequest;
  let response: UpdateBypassersForSourceResponse;

  try {
    request = UpdateBypassersForSourceRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UpdateBypassersForSourceRequest,
      UpdateBypassersForSourceResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateBypassersForSource(ctx, inputReq);
    });
  } else {
    response = await service.UpdateBypassersForSource(ctx, request!);
  }

  return Buffer.from(UpdateBypassersForSourceResponse.toBinary(response));
}

async function handleBypasserAPIGetBypassersProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BypasserAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetBypassersRequest, GetBypassersResponse>[]
) {
  let request: GetBypassersRequest;
  let response: GetBypassersResponse;

  try {
    request = GetBypassersRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBypassersRequest,
      GetBypassersResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassers(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassers(ctx, request!);
  }

  return Buffer.from(GetBypassersResponse.toBinary(response));
}
