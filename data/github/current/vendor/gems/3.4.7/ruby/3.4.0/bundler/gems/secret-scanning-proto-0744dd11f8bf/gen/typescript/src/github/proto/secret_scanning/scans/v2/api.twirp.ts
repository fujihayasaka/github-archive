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
  AddBypassReviewerRequest,
  AddBypassReviewerResponse,
  RemoveBypassReviewerRequest,
  RemoveBypassReviewersForSourceRequest,
  UpdateBypassReviewersForSourceRequest,
  UpdateBypassReviewersForSourceResponse,
  GetBypassReviewersRequest,
  GetBypassReviewersResponse,
  ScanFilesRequest,
  ScanFilesResponse,
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

export interface ScansAPIClient {
  ScanPush(request: ScanPushRequest): Promise<ScanPushResponse>;
  ScanBytes(request: ScanBytesRequest): Promise<ScanBytesResponse>;
  AddBypassReviewer(
    request: AddBypassReviewerRequest
  ): Promise<AddBypassReviewerResponse>;
  RemoveBypassReviewer(request: RemoveBypassReviewerRequest): Promise<Empty>;
  RemoveBypassReviewersForSource(
    request: RemoveBypassReviewersForSourceRequest
  ): Promise<Empty>;
  UpdateBypassReviewersForSource(
    request: UpdateBypassReviewersForSourceRequest
  ): Promise<UpdateBypassReviewersForSourceResponse>;
  GetBypassReviewers(
    request: GetBypassReviewersRequest
  ): Promise<GetBypassReviewersResponse>;
  ScanFiles(request: ScanFilesRequest): Promise<ScanFilesResponse>;
}

export class ScansAPIClientJSON implements ScansAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ScanPush.bind(this);
    this.ScanBytes.bind(this);
    this.AddBypassReviewer.bind(this);
    this.RemoveBypassReviewer.bind(this);
    this.RemoveBypassReviewersForSource.bind(this);
    this.UpdateBypassReviewersForSource.bind(this);
    this.GetBypassReviewers.bind(this);
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

  AddBypassReviewer(
    request: AddBypassReviewerRequest
  ): Promise<AddBypassReviewerResponse> {
    const data = AddBypassReviewerRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "AddBypassReviewer",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      AddBypassReviewerResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  RemoveBypassReviewer(request: RemoveBypassReviewerRequest): Promise<Empty> {
    const data = RemoveBypassReviewerRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "RemoveBypassReviewer",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  RemoveBypassReviewersForSource(
    request: RemoveBypassReviewersForSourceRequest
  ): Promise<Empty> {
    const data = RemoveBypassReviewersForSourceRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "RemoveBypassReviewersForSource",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      Empty.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  UpdateBypassReviewersForSource(
    request: UpdateBypassReviewersForSourceRequest
  ): Promise<UpdateBypassReviewersForSourceResponse> {
    const data = UpdateBypassReviewersForSourceRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "UpdateBypassReviewersForSource",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      UpdateBypassReviewersForSourceResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetBypassReviewers(
    request: GetBypassReviewersRequest
  ): Promise<GetBypassReviewersResponse> {
    const data = GetBypassReviewersRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "GetBypassReviewers",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBypassReviewersResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
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
    this.AddBypassReviewer.bind(this);
    this.RemoveBypassReviewer.bind(this);
    this.RemoveBypassReviewersForSource.bind(this);
    this.UpdateBypassReviewersForSource.bind(this);
    this.GetBypassReviewers.bind(this);
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

  AddBypassReviewer(
    request: AddBypassReviewerRequest
  ): Promise<AddBypassReviewerResponse> {
    const data = AddBypassReviewerRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "AddBypassReviewer",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      AddBypassReviewerResponse.fromBinary(data as Uint8Array)
    );
  }

  RemoveBypassReviewer(request: RemoveBypassReviewerRequest): Promise<Empty> {
    const data = RemoveBypassReviewerRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "RemoveBypassReviewer",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  RemoveBypassReviewersForSource(
    request: RemoveBypassReviewersForSourceRequest
  ): Promise<Empty> {
    const data = RemoveBypassReviewersForSourceRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "RemoveBypassReviewersForSource",
      "application/protobuf",
      data
    );
    return promise.then((data) => Empty.fromBinary(data as Uint8Array));
  }

  UpdateBypassReviewersForSource(
    request: UpdateBypassReviewersForSourceRequest
  ): Promise<UpdateBypassReviewersForSourceResponse> {
    const data = UpdateBypassReviewersForSourceRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "UpdateBypassReviewersForSource",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      UpdateBypassReviewersForSourceResponse.fromBinary(data as Uint8Array)
    );
  }

  GetBypassReviewers(
    request: GetBypassReviewersRequest
  ): Promise<GetBypassReviewersResponse> {
    const data = GetBypassReviewersRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.scans.v2.ScansAPI",
      "GetBypassReviewers",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBypassReviewersResponse.fromBinary(data as Uint8Array)
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
  AddBypassReviewer(
    ctx: T,
    request: AddBypassReviewerRequest
  ): Promise<AddBypassReviewerResponse>;
  RemoveBypassReviewer(
    ctx: T,
    request: RemoveBypassReviewerRequest
  ): Promise<Empty>;
  RemoveBypassReviewersForSource(
    ctx: T,
    request: RemoveBypassReviewersForSourceRequest
  ): Promise<Empty>;
  UpdateBypassReviewersForSource(
    ctx: T,
    request: UpdateBypassReviewersForSourceRequest
  ): Promise<UpdateBypassReviewersForSourceResponse>;
  GetBypassReviewers(
    ctx: T,
    request: GetBypassReviewersRequest
  ): Promise<GetBypassReviewersResponse>;
  ScanFiles(ctx: T, request: ScanFilesRequest): Promise<ScanFilesResponse>;
}

export enum ScansAPIMethod {
  ScanPush = "ScanPush",
  ScanBytes = "ScanBytes",
  AddBypassReviewer = "AddBypassReviewer",
  RemoveBypassReviewer = "RemoveBypassReviewer",
  RemoveBypassReviewersForSource = "RemoveBypassReviewersForSource",
  UpdateBypassReviewersForSource = "UpdateBypassReviewersForSource",
  GetBypassReviewers = "GetBypassReviewers",
  ScanFiles = "ScanFiles",
}

export const ScansAPIMethodList = [
  ScansAPIMethod.ScanPush,
  ScansAPIMethod.ScanBytes,
  ScansAPIMethod.AddBypassReviewer,
  ScansAPIMethod.RemoveBypassReviewer,
  ScansAPIMethod.RemoveBypassReviewersForSource,
  ScansAPIMethod.UpdateBypassReviewersForSource,
  ScansAPIMethod.GetBypassReviewers,
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
    case "AddBypassReviewer":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          AddBypassReviewerRequest,
          AddBypassReviewerResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "AddBypassReviewer" };
        await events.onMatch(ctx);
        return handleScansAPIAddBypassReviewerRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "RemoveBypassReviewer":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, RemoveBypassReviewerRequest, Empty>[]
      ) => {
        ctx = { ...ctx, methodName: "RemoveBypassReviewer" };
        await events.onMatch(ctx);
        return handleScansAPIRemoveBypassReviewerRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "RemoveBypassReviewersForSource":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          RemoveBypassReviewersForSourceRequest,
          Empty
        >[]
      ) => {
        ctx = { ...ctx, methodName: "RemoveBypassReviewersForSource" };
        await events.onMatch(ctx);
        return handleScansAPIRemoveBypassReviewersForSourceRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "UpdateBypassReviewersForSource":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          UpdateBypassReviewersForSourceRequest,
          UpdateBypassReviewersForSourceResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "UpdateBypassReviewersForSource" };
        await events.onMatch(ctx);
        return handleScansAPIUpdateBypassReviewersForSourceRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetBypassReviewers":
      return async (
        ctx: T,
        service: ScansAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetBypassReviewersRequest,
          GetBypassReviewersResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetBypassReviewers" };
        await events.onMatch(ctx);
        return handleScansAPIGetBypassReviewersRequest(
          ctx,
          service,
          data,
          interceptors
        );
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

function handleScansAPIAddBypassReviewerRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    AddBypassReviewerRequest,
    AddBypassReviewerResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIAddBypassReviewerJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScansAPIAddBypassReviewerProtobuf<T>(
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

function handleScansAPIRemoveBypassReviewerRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassReviewerRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIRemoveBypassReviewerJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScansAPIRemoveBypassReviewerProtobuf<T>(
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

function handleScansAPIRemoveBypassReviewersForSourceRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassReviewersForSourceRequest, Empty>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIRemoveBypassReviewersForSourceJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScansAPIRemoveBypassReviewersForSourceProtobuf<T>(
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

function handleScansAPIUpdateBypassReviewersForSourceRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateBypassReviewersForSourceRequest,
    UpdateBypassReviewersForSourceResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIUpdateBypassReviewersForSourceJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScansAPIUpdateBypassReviewersForSourceProtobuf<T>(
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

function handleScansAPIGetBypassReviewersRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassReviewersRequest,
    GetBypassReviewersResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScansAPIGetBypassReviewersJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScansAPIGetBypassReviewersProtobuf<T>(
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

async function handleScansAPIAddBypassReviewerJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    AddBypassReviewerRequest,
    AddBypassReviewerResponse
  >[]
) {
  let request: AddBypassReviewerRequest;
  let response: AddBypassReviewerResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = AddBypassReviewerRequest.fromJson(body, {
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
      AddBypassReviewerRequest,
      AddBypassReviewerResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddBypassReviewer(ctx, inputReq);
    });
  } else {
    response = await service.AddBypassReviewer(ctx, request!);
  }

  return JSON.stringify(
    AddBypassReviewerResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIRemoveBypassReviewerJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassReviewerRequest, Empty>[]
) {
  let request: RemoveBypassReviewerRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = RemoveBypassReviewerRequest.fromJson(body, {
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
      RemoveBypassReviewerRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypassReviewer(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypassReviewer(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIRemoveBypassReviewersForSourceJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassReviewersForSourceRequest, Empty>[]
) {
  let request: RemoveBypassReviewersForSourceRequest;
  let response: Empty;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = RemoveBypassReviewersForSourceRequest.fromJson(body, {
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
      RemoveBypassReviewersForSourceRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypassReviewersForSource(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypassReviewersForSource(ctx, request!);
  }

  return JSON.stringify(
    Empty.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIUpdateBypassReviewersForSourceJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateBypassReviewersForSourceRequest,
    UpdateBypassReviewersForSourceResponse
  >[]
) {
  let request: UpdateBypassReviewersForSourceRequest;
  let response: UpdateBypassReviewersForSourceResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = UpdateBypassReviewersForSourceRequest.fromJson(body, {
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
      UpdateBypassReviewersForSourceRequest,
      UpdateBypassReviewersForSourceResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateBypassReviewersForSource(ctx, inputReq);
    });
  } else {
    response = await service.UpdateBypassReviewersForSource(ctx, request!);
  }

  return JSON.stringify(
    UpdateBypassReviewersForSourceResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleScansAPIGetBypassReviewersJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassReviewersRequest,
    GetBypassReviewersResponse
  >[]
) {
  let request: GetBypassReviewersRequest;
  let response: GetBypassReviewersResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBypassReviewersRequest.fromJson(body, {
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
      GetBypassReviewersRequest,
      GetBypassReviewersResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassReviewers(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassReviewers(ctx, request!);
  }

  return JSON.stringify(
    GetBypassReviewersResponse.toJson(response, {
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

async function handleScansAPIAddBypassReviewerProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    AddBypassReviewerRequest,
    AddBypassReviewerResponse
  >[]
) {
  let request: AddBypassReviewerRequest;
  let response: AddBypassReviewerResponse;

  try {
    request = AddBypassReviewerRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      AddBypassReviewerRequest,
      AddBypassReviewerResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.AddBypassReviewer(ctx, inputReq);
    });
  } else {
    response = await service.AddBypassReviewer(ctx, request!);
  }

  return Buffer.from(AddBypassReviewerResponse.toBinary(response));
}

async function handleScansAPIRemoveBypassReviewerProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassReviewerRequest, Empty>[]
) {
  let request: RemoveBypassReviewerRequest;
  let response: Empty;

  try {
    request = RemoveBypassReviewerRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      RemoveBypassReviewerRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypassReviewer(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypassReviewer(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleScansAPIRemoveBypassReviewersForSourceProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, RemoveBypassReviewersForSourceRequest, Empty>[]
) {
  let request: RemoveBypassReviewersForSourceRequest;
  let response: Empty;

  try {
    request = RemoveBypassReviewersForSourceRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      RemoveBypassReviewersForSourceRequest,
      Empty
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.RemoveBypassReviewersForSource(ctx, inputReq);
    });
  } else {
    response = await service.RemoveBypassReviewersForSource(ctx, request!);
  }

  return Buffer.from(Empty.toBinary(response));
}

async function handleScansAPIUpdateBypassReviewersForSourceProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    UpdateBypassReviewersForSourceRequest,
    UpdateBypassReviewersForSourceResponse
  >[]
) {
  let request: UpdateBypassReviewersForSourceRequest;
  let response: UpdateBypassReviewersForSourceResponse;

  try {
    request = UpdateBypassReviewersForSourceRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      UpdateBypassReviewersForSourceRequest,
      UpdateBypassReviewersForSourceResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.UpdateBypassReviewersForSource(ctx, inputReq);
    });
  } else {
    response = await service.UpdateBypassReviewersForSource(ctx, request!);
  }

  return Buffer.from(UpdateBypassReviewersForSourceResponse.toBinary(response));
}

async function handleScansAPIGetBypassReviewersProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScansAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetBypassReviewersRequest,
    GetBypassReviewersResponse
  >[]
) {
  let request: GetBypassReviewersRequest;
  let response: GetBypassReviewersResponse;

  try {
    request = GetBypassReviewersRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBypassReviewersRequest,
      GetBypassReviewersResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBypassReviewers(ctx, inputReq);
    });
  } else {
    response = await service.GetBypassReviewers(ctx, request!);
  }

  return Buffer.from(GetBypassReviewersResponse.toBinary(response));
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
