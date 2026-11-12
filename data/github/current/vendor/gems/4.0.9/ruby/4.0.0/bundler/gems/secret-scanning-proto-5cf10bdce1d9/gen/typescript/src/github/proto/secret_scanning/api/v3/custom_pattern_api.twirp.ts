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
  GetCustomPatternsRequest,
  GetCustomPatternsResponse,
  GetCustomPatternsCountRequest,
  GetCustomPatternsCountResponse,
  UpdateCustomPatternSettingsRequest,
  UpdateCustomPatternSettingsResponse,
  DeleteCustomPatternsRequest,
  DeleteCustomPatternsResponse,
  GetGeneratedExpressionsRequest,
  GetGeneratedExpressionsResponse,
  BatchCreateCustomPatternsRequest,
  BatchCreateCustomPatternsResponse,
} from "./custom_pattern_api";

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
  GetCustomPatterns(
    request: GetCustomPatternsRequest
  ): Promise<GetCustomPatternsResponse>;
  GetCustomPatternsCount(
    request: GetCustomPatternsCountRequest
  ): Promise<GetCustomPatternsCountResponse>;
  UpdateCustomPatternSettings(
    request: UpdateCustomPatternSettingsRequest
  ): Promise<UpdateCustomPatternSettingsResponse>;
  DeleteCustomPatterns(
    request: DeleteCustomPatternsRequest
  ): Promise<DeleteCustomPatternsResponse>;
  GetGeneratedExpressions(
    request: GetGeneratedExpressionsRequest
  ): Promise<GetGeneratedExpressionsResponse>;
  BatchCreateCustomPatterns(
    request: BatchCreateCustomPatternsRequest
  ): Promise<BatchCreateCustomPatternsResponse>;
}

export class CustomPatternAPIClientJSON implements CustomPatternAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetCustomPatterns.bind(this);
    this.GetCustomPatternsCount.bind(this);
    this.UpdateCustomPatternSettings.bind(this);
    this.DeleteCustomPatterns.bind(this);
    this.GetGeneratedExpressions.bind(this);
    this.BatchCreateCustomPatterns.bind(this);
  }
  GetCustomPatterns(
    request: GetCustomPatternsRequest
  ): Promise<GetCustomPatternsResponse> {
    const data = GetCustomPatternsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "GetCustomPatterns",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetCustomPatternsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetCustomPatternsCount(
    request: GetCustomPatternsCountRequest
  ): Promise<GetCustomPatternsCountResponse> {
    const data = GetCustomPatternsCountRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "GetCustomPatternsCount",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetCustomPatternsCountResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  UpdateCustomPatternSettings(
    request: UpdateCustomPatternSettingsRequest
  ): Promise<UpdateCustomPatternSettingsResponse> {
    const data = UpdateCustomPatternSettingsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "UpdateCustomPatternSettings",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      UpdateCustomPatternSettingsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  DeleteCustomPatterns(
    request: DeleteCustomPatternsRequest
  ): Promise<DeleteCustomPatternsResponse> {
    const data = DeleteCustomPatternsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "DeleteCustomPatterns",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      DeleteCustomPatternsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetGeneratedExpressions(
    request: GetGeneratedExpressionsRequest
  ): Promise<GetGeneratedExpressionsResponse> {
    const data = GetGeneratedExpressionsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "GetGeneratedExpressions",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetGeneratedExpressionsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  BatchCreateCustomPatterns(
    request: BatchCreateCustomPatternsRequest
  ): Promise<BatchCreateCustomPatternsResponse> {
    const data = BatchCreateCustomPatternsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "BatchCreateCustomPatterns",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      BatchCreateCustomPatternsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class CustomPatternAPIClientProtobuf implements CustomPatternAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetCustomPatterns.bind(this);
    this.GetCustomPatternsCount.bind(this);
    this.UpdateCustomPatternSettings.bind(this);
    this.DeleteCustomPatterns.bind(this);
    this.GetGeneratedExpressions.bind(this);
    this.BatchCreateCustomPatterns.bind(this);
  }
  GetCustomPatterns(
    request: GetCustomPatternsRequest
  ): Promise<GetCustomPatternsResponse> {
    const data = GetCustomPatternsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "GetCustomPatterns",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetCustomPatternsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetCustomPatternsCount(
    request: GetCustomPatternsCountRequest
  ): Promise<GetCustomPatternsCountResponse> {
    const data = GetCustomPatternsCountRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "GetCustomPatternsCount",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetCustomPatternsCountResponse.fromBinary(data as Uint8Array)
    );
  }

  UpdateCustomPatternSettings(
    request: UpdateCustomPatternSettingsRequest
  ): Promise<UpdateCustomPatternSettingsResponse> {
    const data = UpdateCustomPatternSettingsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "UpdateCustomPatternSettings",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      UpdateCustomPatternSettingsResponse.fromBinary(data as Uint8Array)
    );
  }

  DeleteCustomPatterns(
    request: DeleteCustomPatternsRequest
  ): Promise<DeleteCustomPatternsResponse> {
    const data = DeleteCustomPatternsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "DeleteCustomPatterns",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      DeleteCustomPatternsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetGeneratedExpressions(
    request: GetGeneratedExpressionsRequest
  ): Promise<GetGeneratedExpressionsResponse> {
    const data = GetGeneratedExpressionsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "GetGeneratedExpressions",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetGeneratedExpressionsResponse.fromBinary(data as Uint8Array)
    );
  }

  BatchCreateCustomPatterns(
    request: BatchCreateCustomPatternsRequest
  ): Promise<BatchCreateCustomPatternsResponse> {
    const data = BatchCreateCustomPatternsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v3.CustomPatternAPI",
      "BatchCreateCustomPatterns",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      BatchCreateCustomPatternsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface CustomPatternAPITwirp<T extends TwirpContext = TwirpContext> {
  GetCustomPatterns(
    ctx: T,
    request: GetCustomPatternsRequest
  ): Promise<GetCustomPatternsResponse>;
  GetCustomPatternsCount(
    ctx: T,
    request: GetCustomPatternsCountRequest
  ): Promise<GetCustomPatternsCountResponse>;
  UpdateCustomPatternSettings(
    ctx: T,
    request: UpdateCustomPatternSettingsRequest
  ): Promise<UpdateCustomPatternSettingsResponse>;
  DeleteCustomPatterns(
    ctx: T,
    request: DeleteCustomPatternsRequest
  ): Promise<DeleteCustomPatternsResponse>;
  GetGeneratedExpressions(
    ctx: T,
    request: GetGeneratedExpressionsRequest
  ): Promise<GetGeneratedExpressionsResponse>;
  BatchCreateCustomPatterns(
    ctx: T,
    request: BatchCreateCustomPatternsRequest
  ): Promise<BatchCreateCustomPatternsResponse>;
}

export enum CustomPatternAPIMethod {
  GetCustomPatterns = "GetCustomPatterns",
  GetCustomPatternsCount = "GetCustomPatternsCount",
  UpdateCustomPatternSettings = "UpdateCustomPatternSettings",
  DeleteCustomPatterns = "DeleteCustomPatterns",
  GetGeneratedExpressions = "GetGeneratedExpressions",
  BatchCreateCustomPatterns = "BatchCreateCustomPatterns",
}

export const CustomPatternAPIMethodList = [
  CustomPatternAPIMethod.GetCustomPatterns,
  CustomPatternAPIMethod.GetCustomPatternsCount,
  CustomPatternAPIMethod.UpdateCustomPatternSettings,
  CustomPatternAPIMethod.DeleteCustomPatterns,
  CustomPatternAPIMethod.GetGeneratedExpressions,
  CustomPatternAPIMethod.BatchCreateCustomPatterns,
];

export function createCustomPatternAPIServer<
  T extends TwirpContext = TwirpContext
>(service: CustomPatternAPITwirp<T>) {
  return new TwirpServer<CustomPatternAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v3",
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
    case "GetCustomPatterns":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetCustomPatternsRequest,
          GetCustomPatternsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetCustomPatterns" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIGetCustomPatternsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetCustomPatternsCount":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetCustomPatternsCountRequest,
          GetCustomPatternsCountResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetCustomPatternsCount" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIGetCustomPatternsCountRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "UpdateCustomPatternSettings":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          UpdateCustomPatternSettingsRequest,
          UpdateCustomPatternSettingsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "UpdateCustomPatternSettings" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIUpdateCustomPatternSettingsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "DeleteCustomPatterns":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          DeleteCustomPatternsRequest,
          DeleteCustomPatternsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "DeleteCustomPatterns" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIDeleteCustomPatternsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetGeneratedExpressions":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetGeneratedExpressionsRequest,
          GetGeneratedExpressionsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetGeneratedExpressions" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIGetGeneratedExpressionsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "BatchCreateCustomPatterns":
      return async (
        ctx: T,
        service: CustomPatternAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          BatchCreateCustomPatternsRequest,
          BatchCreateCustomPatternsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "BatchCreateCustomPatterns" };
        await events.onMatch(ctx);
        return handleCustomPatternAPIBatchCreateCustomPatternsRequest(
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

function handleCustomPatternAPIGetCustomPatternsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternsRequest,
    GetCustomPatternsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIGetCustomPatternsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIGetCustomPatternsProtobuf<T>(
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

function handleCustomPatternAPIGetCustomPatternsCountRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternsCountRequest,
    GetCustomPatternsCountResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIGetCustomPatternsCountJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIGetCustomPatternsCountProtobuf<T>(
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

function handleCustomPatternAPIUpdateCustomPatternSettingsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateCustomPatternSettingsRequest,
    UpdateCustomPatternSettingsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIUpdateCustomPatternSettingsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIUpdateCustomPatternSettingsProtobuf<T>(
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

function handleCustomPatternAPIDeleteCustomPatternsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    DeleteCustomPatternsRequest,
    DeleteCustomPatternsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIDeleteCustomPatternsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIDeleteCustomPatternsProtobuf<T>(
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

function handleCustomPatternAPIGetGeneratedExpressionsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetGeneratedExpressionsRequest,
    GetGeneratedExpressionsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIGetGeneratedExpressionsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIGetGeneratedExpressionsProtobuf<T>(
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

function handleCustomPatternAPIBatchCreateCustomPatternsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    BatchCreateCustomPatternsRequest,
    BatchCreateCustomPatternsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleCustomPatternAPIBatchCreateCustomPatternsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleCustomPatternAPIBatchCreateCustomPatternsProtobuf<T>(
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
async function handleCustomPatternAPIGetCustomPatternsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternsRequest,
    GetCustomPatternsResponse
  >[]
) {
  let request: GetCustomPatternsRequest;
  let response: GetCustomPatternsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetCustomPatternsRequest.fromJson(body, {
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
      GetCustomPatternsRequest,
      GetCustomPatternsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetCustomPatterns(ctx, inputReq);
    });
  } else {
    response = await service.GetCustomPatterns(ctx, request!);
  }

  return JSON.stringify(
    GetCustomPatternsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIGetCustomPatternsCountJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternsCountRequest,
    GetCustomPatternsCountResponse
  >[]
) {
  let request: GetCustomPatternsCountRequest;
  let response: GetCustomPatternsCountResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetCustomPatternsCountRequest.fromJson(body, {
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
      GetCustomPatternsCountRequest,
      GetCustomPatternsCountResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetCustomPatternsCount(ctx, inputReq);
    });
  } else {
    response = await service.GetCustomPatternsCount(ctx, request!);
  }

  return JSON.stringify(
    GetCustomPatternsCountResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIUpdateCustomPatternSettingsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateCustomPatternSettingsRequest,
    UpdateCustomPatternSettingsResponse
  >[]
) {
  let request: UpdateCustomPatternSettingsRequest;
  let response: UpdateCustomPatternSettingsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = UpdateCustomPatternSettingsRequest.fromJson(body, {
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
      UpdateCustomPatternSettingsRequest,
      UpdateCustomPatternSettingsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateCustomPatternSettings(ctx, inputReq);
    });
  } else {
    response = await service.UpdateCustomPatternSettings(ctx, request!);
  }

  return JSON.stringify(
    UpdateCustomPatternSettingsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIDeleteCustomPatternsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    DeleteCustomPatternsRequest,
    DeleteCustomPatternsResponse
  >[]
) {
  let request: DeleteCustomPatternsRequest;
  let response: DeleteCustomPatternsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = DeleteCustomPatternsRequest.fromJson(body, {
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
      DeleteCustomPatternsRequest,
      DeleteCustomPatternsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DeleteCustomPatterns(ctx, inputReq);
    });
  } else {
    response = await service.DeleteCustomPatterns(ctx, request!);
  }

  return JSON.stringify(
    DeleteCustomPatternsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIGetGeneratedExpressionsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetGeneratedExpressionsRequest,
    GetGeneratedExpressionsResponse
  >[]
) {
  let request: GetGeneratedExpressionsRequest;
  let response: GetGeneratedExpressionsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetGeneratedExpressionsRequest.fromJson(body, {
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
      GetGeneratedExpressionsRequest,
      GetGeneratedExpressionsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetGeneratedExpressions(ctx, inputReq);
    });
  } else {
    response = await service.GetGeneratedExpressions(ctx, request!);
  }

  return JSON.stringify(
    GetGeneratedExpressionsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleCustomPatternAPIBatchCreateCustomPatternsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    BatchCreateCustomPatternsRequest,
    BatchCreateCustomPatternsResponse
  >[]
) {
  let request: BatchCreateCustomPatternsRequest;
  let response: BatchCreateCustomPatternsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = BatchCreateCustomPatternsRequest.fromJson(body, {
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
      BatchCreateCustomPatternsRequest,
      BatchCreateCustomPatternsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.BatchCreateCustomPatterns(ctx, inputReq);
    });
  } else {
    response = await service.BatchCreateCustomPatterns(ctx, request!);
  }

  return JSON.stringify(
    BatchCreateCustomPatternsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleCustomPatternAPIGetCustomPatternsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternsRequest,
    GetCustomPatternsResponse
  >[]
) {
  let request: GetCustomPatternsRequest;
  let response: GetCustomPatternsResponse;

  try {
    request = GetCustomPatternsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetCustomPatternsRequest,
      GetCustomPatternsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetCustomPatterns(ctx, inputReq);
    });
  } else {
    response = await service.GetCustomPatterns(ctx, request!);
  }

  return Buffer.from(GetCustomPatternsResponse.toBinary(response));
}

async function handleCustomPatternAPIGetCustomPatternsCountProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetCustomPatternsCountRequest,
    GetCustomPatternsCountResponse
  >[]
) {
  let request: GetCustomPatternsCountRequest;
  let response: GetCustomPatternsCountResponse;

  try {
    request = GetCustomPatternsCountRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetCustomPatternsCountRequest,
      GetCustomPatternsCountResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetCustomPatternsCount(ctx, inputReq);
    });
  } else {
    response = await service.GetCustomPatternsCount(ctx, request!);
  }

  return Buffer.from(GetCustomPatternsCountResponse.toBinary(response));
}

async function handleCustomPatternAPIUpdateCustomPatternSettingsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateCustomPatternSettingsRequest,
    UpdateCustomPatternSettingsResponse
  >[]
) {
  let request: UpdateCustomPatternSettingsRequest;
  let response: UpdateCustomPatternSettingsResponse;

  try {
    request = UpdateCustomPatternSettingsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UpdateCustomPatternSettingsRequest,
      UpdateCustomPatternSettingsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateCustomPatternSettings(ctx, inputReq);
    });
  } else {
    response = await service.UpdateCustomPatternSettings(ctx, request!);
  }

  return Buffer.from(UpdateCustomPatternSettingsResponse.toBinary(response));
}

async function handleCustomPatternAPIDeleteCustomPatternsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    DeleteCustomPatternsRequest,
    DeleteCustomPatternsResponse
  >[]
) {
  let request: DeleteCustomPatternsRequest;
  let response: DeleteCustomPatternsResponse;

  try {
    request = DeleteCustomPatternsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      DeleteCustomPatternsRequest,
      DeleteCustomPatternsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.DeleteCustomPatterns(ctx, inputReq);
    });
  } else {
    response = await service.DeleteCustomPatterns(ctx, request!);
  }

  return Buffer.from(DeleteCustomPatternsResponse.toBinary(response));
}

async function handleCustomPatternAPIGetGeneratedExpressionsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetGeneratedExpressionsRequest,
    GetGeneratedExpressionsResponse
  >[]
) {
  let request: GetGeneratedExpressionsRequest;
  let response: GetGeneratedExpressionsResponse;

  try {
    request = GetGeneratedExpressionsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetGeneratedExpressionsRequest,
      GetGeneratedExpressionsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetGeneratedExpressions(ctx, inputReq);
    });
  } else {
    response = await service.GetGeneratedExpressions(ctx, request!);
  }

  return Buffer.from(GetGeneratedExpressionsResponse.toBinary(response));
}

async function handleCustomPatternAPIBatchCreateCustomPatternsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: CustomPatternAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    BatchCreateCustomPatternsRequest,
    BatchCreateCustomPatternsResponse
  >[]
) {
  let request: BatchCreateCustomPatternsRequest;
  let response: BatchCreateCustomPatternsResponse;

  try {
    request = BatchCreateCustomPatternsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      BatchCreateCustomPatternsRequest,
      BatchCreateCustomPatternsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.BatchCreateCustomPatterns(ctx, inputReq);
    });
  } else {
    response = await service.BatchCreateCustomPatterns(ctx, request!);
  }

  return Buffer.from(BatchCreateCustomPatternsResponse.toBinary(response));
}
