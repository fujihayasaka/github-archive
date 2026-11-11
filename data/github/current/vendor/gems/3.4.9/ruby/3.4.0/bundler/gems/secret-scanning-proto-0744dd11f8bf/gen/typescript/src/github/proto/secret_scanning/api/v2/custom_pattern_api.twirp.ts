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
  GetPatternMatchesRequest,
  GetPatternMatchesResponse,
  GetCustomPatternRequest,
  GetCustomPatternResponse,
  CreateCustomPatternRequest,
  CreateCustomPatternResponse,
  UpdateCustomPatternRequest,
  UpdateCustomPatternResponse,
  DeleteCustomPatternRequest,
  PublishCustomPatternRequest,
} from "./custom_pattern_api";
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

export interface CustomPatternAPIClient {
  GetPatternMatches(
    request: GetPatternMatchesRequest
  ): Promise<GetPatternMatchesResponse>;
  GetCustomPattern(
    request: GetCustomPatternRequest
  ): Promise<GetCustomPatternResponse>;
  CreateCustomPattern(
    request: CreateCustomPatternRequest
  ): Promise<CreateCustomPatternResponse>;
  UpdateCustomPattern(
    request: UpdateCustomPatternRequest
  ): Promise<UpdateCustomPatternResponse>;
  DeleteCustomPattern(request: DeleteCustomPatternRequest): Promise<Empty>;
  PublishCustomPattern(request: PublishCustomPatternRequest): Promise<Empty>;
}

export class CustomPatternAPIClientJSON implements CustomPatternAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetPatternMatches.bind(this);
    this.GetCustomPattern.bind(this);
    this.CreateCustomPattern.bind(this);
    this.UpdateCustomPattern.bind(this);
    this.DeleteCustomPattern.bind(this);
    this.PublishCustomPattern.bind(this);
  }
  GetPatternMatches(
    request: GetPatternMatchesRequest
  ): Promise<GetPatternMatchesResponse> {
    const data = GetPatternMatchesRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "GetPatternMatches",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetPatternMatchesResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetCustomPattern(
    request: GetCustomPatternRequest
  ): Promise<GetCustomPatternResponse> {
    const data = GetCustomPatternRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "GetCustomPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetCustomPatternResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  CreateCustomPattern(
    request: CreateCustomPatternRequest
  ): Promise<CreateCustomPatternResponse> {
    const data = CreateCustomPatternRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "CreateCustomPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      CreateCustomPatternResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  UpdateCustomPattern(
    request: UpdateCustomPatternRequest
  ): Promise<UpdateCustomPatternResponse> {
    const data = UpdateCustomPatternRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "UpdateCustomPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      UpdateCustomPatternResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  DeleteCustomPattern(request: DeleteCustomPatternRequest): Promise<Empty> {
    const data = DeleteCustomPatternRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "DeleteCustomPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  PublishCustomPattern(request: PublishCustomPatternRequest): Promise<Empty> {
    const data = PublishCustomPatternRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "PublishCustomPattern",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class CustomPatternAPIClientProtobuf implements CustomPatternAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetPatternMatches.bind(this);
    this.GetCustomPattern.bind(this);
    this.CreateCustomPattern.bind(this);
    this.UpdateCustomPattern.bind(this);
    this.DeleteCustomPattern.bind(this);
    this.PublishCustomPattern.bind(this);
  }
  GetPatternMatches(
    request: GetPatternMatchesRequest
  ): Promise<GetPatternMatchesResponse> {
    const data = GetPatternMatchesRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "GetPatternMatches",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetPatternMatchesResponse.fromBinary(data as Uint8Array)
    );
  }

  GetCustomPattern(
    request: GetCustomPatternRequest
  ): Promise<GetCustomPatternResponse> {
    const data = GetCustomPatternRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "GetCustomPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetCustomPatternResponse.fromBinary(data as Uint8Array)
    );
  }

  CreateCustomPattern(
    request: CreateCustomPatternRequest
  ): Promise<CreateCustomPatternResponse> {
    const data = CreateCustomPatternRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "CreateCustomPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      CreateCustomPatternResponse.fromBinary(data as Uint8Array)
    );
  }

  UpdateCustomPattern(
    request: UpdateCustomPatternRequest
  ): Promise<UpdateCustomPatternResponse> {
    const data = UpdateCustomPatternRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "UpdateCustomPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      UpdateCustomPatternResponse.fromBinary(data as Uint8Array)
    );
  }

  DeleteCustomPattern(request: DeleteCustomPatternRequest): Promise<Empty> {
    const data = DeleteCustomPatternRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "DeleteCustomPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  PublishCustomPattern(request: PublishCustomPatternRequest): Promise<Empty> {
    const data = PublishCustomPatternRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v2.CustomPatternAPI",
      "PublishCustomPattern",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface CustomPatternAPITwirp<T extends TwirpContext = TwirpContext> {
  GetPatternMatches(
    ctx: T,
    request: GetPatternMatchesRequest
  ): Promise<GetPatternMatchesResponse>;
  GetCustomPattern(
    ctx: T,
    request: GetCustomPatternRequest
  ): Promise<GetCustomPatternResponse>;
  CreateCustomPattern(
    ctx: T,
    request: CreateCustomPatternRequest
  ): Promise<CreateCustomPatternResponse>;
  UpdateCustomPattern(
    ctx: T,
    request: UpdateCustomPatternRequest
  ): Promise<UpdateCustomPatternResponse>;
  DeleteCustomPattern(
    ctx: T,
    request: DeleteCustomPatternRequest
  ): Promise<Empty>;
  PublishCustomPattern(
    ctx: T,
    request: PublishCustomPatternRequest
  ): Promise<Empty>;
}

export enum CustomPatternAPIMethod {
  GetPatternMatches = "GetPatternMatches",
  GetCustomPattern = "GetCustomPattern",
  CreateCustomPattern = "CreateCustomPattern",
  UpdateCustomPattern = "UpdateCustomPattern",
  DeleteCustomPattern = "DeleteCustomPattern",
  PublishCustomPattern = "PublishCustomPattern",
}

export const CustomPatternAPIMethodList = [
  CustomPatternAPIMethod.GetPatternMatches,
  CustomPatternAPIMethod.GetCustomPattern,
  CustomPatternAPIMethod.CreateCustomPattern,
  CustomPatternAPIMethod.UpdateCustomPattern,
  CustomPatternAPIMethod.DeleteCustomPattern,
  CustomPatternAPIMethod.PublishCustomPattern,
];

export function createCustomPatternAPIServer<
  T extends TwirpContext = TwirpContext
>(service: CustomPatternAPITwirp<T>) {
  return new TwirpServer<CustomPatternAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v2",
    serviceName: "CustomPatternAPI",
    methodList: CustomPatternAPIMethodList,
    matchRoute: matchCustomPatternAPIRoute,
  });
}

function matchCustomPatternAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetPatternMatches":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetPatternMatchesRequest,
          GetPatternMatchesResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetPatternMatches" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIGetPatternMatchesRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetCustomPattern":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetCustomPatternRequest,
          GetCustomPatternResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetCustomPattern" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIGetCustomPatternRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "CreateCustomPattern":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          CreateCustomPatternRequest,
          CreateCustomPatternResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "CreateCustomPattern" };
        await events.onMatch(ctx);
        return handleCustomPatternAPICreateCustomPatternRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "UpdateCustomPattern":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          UpdateCustomPatternRequest,
          UpdateCustomPatternResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "UpdateCustomPattern" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIUpdateCustomPatternRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "DeleteCustomPattern":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, DeleteCustomPatternRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "DeleteCustomPattern" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIDeleteCustomPatternRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "PublishCustomPattern":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, PublishCustomPatternRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "PublishCustomPattern" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIPublishCustomPatternRequest(
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

function handleCustomPatternAPIGetPatternMatchesRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPatternMatchesRequest,
    GetPatternMatchesResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIGetPatternMatchesJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIGetPatternMatchesProtobuf<T>(
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

function handleCustomPatternAPIGetCustomPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternRequest,
    GetCustomPatternResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIGetCustomPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIGetCustomPatternProtobuf<T>(
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

function handleCustomPatternAPICreateCustomPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CreateCustomPatternRequest,
    CreateCustomPatternResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPICreateCustomPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPICreateCustomPatternProtobuf<T>(
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

function handleCustomPatternAPIUpdateCustomPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateCustomPatternRequest,
    UpdateCustomPatternResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIUpdateCustomPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIUpdateCustomPatternProtobuf<T>(
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

function handleCustomPatternAPIDeleteCustomPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, DeleteCustomPatternRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIDeleteCustomPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIDeleteCustomPatternProtobuf<T>(
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

function handleCustomPatternAPIPublishCustomPatternRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, PublishCustomPatternRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIPublishCustomPatternJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIPublishCustomPatternProtobuf<T>(
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
async function handleCustomPatternAPIGetPatternMatchesJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPatternMatchesRequest,
    GetPatternMatchesResponse
  >[]
) {
  let request: GetPatternMatchesRequest;
  let response: GetPatternMatchesResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetPatternMatchesRequest.fromJson(body, {
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
      GetPatternMatchesRequest,
      GetPatternMatchesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPatternMatches(ctx, inputReq);
    });
  } else {
    response = await service.GetPatternMatches(ctx, request!);
  }

  return JSON.stringify(
    GetPatternMatchesResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIGetCustomPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternRequest,
    GetCustomPatternResponse
  >[]
) {
  let request: GetCustomPatternRequest;
  let response: GetCustomPatternResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetCustomPatternRequest.fromJson(body, {
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
      GetCustomPatternRequest,
      GetCustomPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.GetCustomPattern(ctx, request!);
  }

  return JSON.stringify(
    GetCustomPatternResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPICreateCustomPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CreateCustomPatternRequest,
    CreateCustomPatternResponse
  >[]
) {
  let request: CreateCustomPatternRequest;
  let response: CreateCustomPatternResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = CreateCustomPatternRequest.fromJson(body, {
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
      CreateCustomPatternRequest,
      CreateCustomPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CreateCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.CreateCustomPattern(ctx, request!);
  }

  return JSON.stringify(
    CreateCustomPatternResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIUpdateCustomPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateCustomPatternRequest,
    UpdateCustomPatternResponse
  >[]
) {
  let request: UpdateCustomPatternRequest;
  let response: UpdateCustomPatternResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = UpdateCustomPatternRequest.fromJson(body, {
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
      UpdateCustomPatternRequest,
      UpdateCustomPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.UpdateCustomPattern(ctx, request!);
  }

  return JSON.stringify(
    UpdateCustomPatternResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIDeleteCustomPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, DeleteCustomPatternRequest, Empty>[]
) {
  let request: DeleteCustomPatternRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = DeleteCustomPatternRequest.fromJson(body, {
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
      DeleteCustomPatternRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DeleteCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.DeleteCustomPattern(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIPublishCustomPatternJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, PublishCustomPatternRequest, Empty>[]
) {
  let request: PublishCustomPatternRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = PublishCustomPatternRequest.fromJson(body, {
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
      PublishCustomPatternRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.PublishCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.PublishCustomPattern(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleCustomPatternAPIGetPatternMatchesProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetPatternMatchesRequest,
    GetPatternMatchesResponse
  >[]
) {
  let request: GetPatternMatchesRequest;
  let response: GetPatternMatchesResponse;

  try {
    request = GetPatternMatchesRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetPatternMatchesRequest,
      GetPatternMatchesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetPatternMatches(ctx, inputReq);
    });
  } else {
    response = await service.GetPatternMatches(ctx, request!);
  }

  return Buffer.from(GetPatternMatchesResponse.toBinary(response));
}

async function handleCustomPatternAPIGetCustomPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternRequest,
    GetCustomPatternResponse
  >[]
) {
  let request: GetCustomPatternRequest;
  let response: GetCustomPatternResponse;

  try {
    request = GetCustomPatternRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetCustomPatternRequest,
      GetCustomPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.GetCustomPattern(ctx, request!);
  }

  return Buffer.from(GetCustomPatternResponse.toBinary(response));
}

async function handleCustomPatternAPICreateCustomPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CreateCustomPatternRequest,
    CreateCustomPatternResponse
  >[]
) {
  let request: CreateCustomPatternRequest;
  let response: CreateCustomPatternResponse;

  try {
    request = CreateCustomPatternRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CreateCustomPatternRequest,
      CreateCustomPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CreateCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.CreateCustomPattern(ctx, request!);
  }

  return Buffer.from(CreateCustomPatternResponse.toBinary(response));
}

async function handleCustomPatternAPIUpdateCustomPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateCustomPatternRequest,
    UpdateCustomPatternResponse
  >[]
) {
  let request: UpdateCustomPatternRequest;
  let response: UpdateCustomPatternResponse;

  try {
    request = UpdateCustomPatternRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UpdateCustomPatternRequest,
      UpdateCustomPatternResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.UpdateCustomPattern(ctx, request!);
  }

  return Buffer.from(UpdateCustomPatternResponse.toBinary(response));
}

async function handleCustomPatternAPIDeleteCustomPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, DeleteCustomPatternRequest, Empty>[]
) {
  let request: DeleteCustomPatternRequest;
  let response: Empty;

  try {
    request = DeleteCustomPatternRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      DeleteCustomPatternRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DeleteCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.DeleteCustomPattern(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleCustomPatternAPIPublishCustomPatternProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, PublishCustomPatternRequest, Empty>[]
) {
  let request: PublishCustomPatternRequest;
  let response: Empty;

  try {
    request = PublishCustomPatternRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      PublishCustomPatternRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.PublishCustomPattern(ctx, inputReq);
    });
  } else {
    response = await service.PublishCustomPattern(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}
