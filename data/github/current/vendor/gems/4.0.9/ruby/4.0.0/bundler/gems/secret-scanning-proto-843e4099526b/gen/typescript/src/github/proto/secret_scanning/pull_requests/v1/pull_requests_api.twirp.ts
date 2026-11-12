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
  ListPullRequestsRequest,
  ListPullRequestsResponse,
  StreamPullRequestContentRequest,
  StreamPullRequestContentResponse,
} from "./pull_requests_api";

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

export interface PullRequestsAPIClient {
  ListPullRequests(
    request: ListPullRequestsRequest
  ): Promise<ListPullRequestsResponse>;
  StreamPullRequestContent(
    request: StreamPullRequestContentRequest
  ): Promise<StreamPullRequestContentResponse>;
}

export class PullRequestsAPIClientJSON implements PullRequestsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ListPullRequests.bind(this);
    this.StreamPullRequestContent.bind(this);
  }
  ListPullRequests(
    request: ListPullRequestsRequest
  ): Promise<ListPullRequestsResponse> {
    const data = ListPullRequestsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.pull_requests.v1.PullRequestsAPI",
      "ListPullRequests",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListPullRequestsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  StreamPullRequestContent(
    request: StreamPullRequestContentRequest
  ): Promise<StreamPullRequestContentResponse> {
    const data = StreamPullRequestContentRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.pull_requests.v1.PullRequestsAPI",
      "StreamPullRequestContent",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      StreamPullRequestContentResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class PullRequestsAPIClientProtobuf implements PullRequestsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ListPullRequests.bind(this);
    this.StreamPullRequestContent.bind(this);
  }
  ListPullRequests(
    request: ListPullRequestsRequest
  ): Promise<ListPullRequestsResponse> {
    const data = ListPullRequestsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.pull_requests.v1.PullRequestsAPI",
      "ListPullRequests",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListPullRequestsResponse.fromBinary(data as Uint8Array)
    );
  }

  StreamPullRequestContent(
    request: StreamPullRequestContentRequest
  ): Promise<StreamPullRequestContentResponse> {
    const data = StreamPullRequestContentRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.pull_requests.v1.PullRequestsAPI",
      "StreamPullRequestContent",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      StreamPullRequestContentResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface PullRequestsAPITwirp<T extends TwirpContext = TwirpContext> {
  ListPullRequests(
    ctx: T,
    request: ListPullRequestsRequest
  ): Promise<ListPullRequestsResponse>;
  StreamPullRequestContent(
    ctx: T,
    request: StreamPullRequestContentRequest
  ): Promise<StreamPullRequestContentResponse>;
}

export enum PullRequestsAPIMethod {
  ListPullRequests = "ListPullRequests",
  StreamPullRequestContent = "StreamPullRequestContent",
}

export const PullRequestsAPIMethodList = [
  PullRequestsAPIMethod.ListPullRequests,
  PullRequestsAPIMethod.StreamPullRequestContent,
];

export function createPullRequestsAPIServer<
  T extends TwirpContext = TwirpContext
>(service: PullRequestsAPITwirp<T>) {
  return new TwirpServer<PullRequestsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.pull_requests.v1",
    serviceName: "PullRequestsAPI",
    methodList: PullRequestsAPIMethodList,
    matchRoute: matchPullRequestsAPIRoute,
  });
}

function matchPullRequestsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "ListPullRequests":
      return async (
        ctx: T,
        service: PullRequestsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ListPullRequestsRequest,
          ListPullRequestsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ListPullRequests" };
        await events.onMatch(ctx);
        return handlePullRequestsAPIListPullRequestsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "StreamPullRequestContent":
      return async (
        ctx: T,
        service: PullRequestsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          StreamPullRequestContentRequest,
          StreamPullRequestContentResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "StreamPullRequestContent" };
        await events.onMatch(ctx);
        return handlePullRequestsAPIStreamPullRequestContentRequest(
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

function handlePullRequestsAPIListPullRequestsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PullRequestsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListPullRequestsRequest,
    ListPullRequestsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePullRequestsAPIListPullRequestsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePullRequestsAPIListPullRequestsProtobuf<T>(
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

function handlePullRequestsAPIStreamPullRequestContentRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PullRequestsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    StreamPullRequestContentRequest,
    StreamPullRequestContentResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePullRequestsAPIStreamPullRequestContentJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePullRequestsAPIStreamPullRequestContentProtobuf<T>(
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
async function handlePullRequestsAPIListPullRequestsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PullRequestsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListPullRequestsRequest,
    ListPullRequestsResponse
  >[]
) {
  let request: ListPullRequestsRequest;
  let response: ListPullRequestsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListPullRequestsRequest.fromJson(body, {
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
      ListPullRequestsRequest,
      ListPullRequestsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListPullRequests(ctx, inputReq);
    });
  } else {
    response = await service.ListPullRequests(ctx, request!);
  }

  return JSON.stringify(
    ListPullRequestsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handlePullRequestsAPIStreamPullRequestContentJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PullRequestsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    StreamPullRequestContentRequest,
    StreamPullRequestContentResponse
  >[]
) {
  let request: StreamPullRequestContentRequest;
  let response: StreamPullRequestContentResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = StreamPullRequestContentRequest.fromJson(body, {
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
      StreamPullRequestContentRequest,
      StreamPullRequestContentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.StreamPullRequestContent(ctx, inputReq);
    });
  } else {
    response = await service.StreamPullRequestContent(ctx, request!);
  }

  return JSON.stringify(
    StreamPullRequestContentResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handlePullRequestsAPIListPullRequestsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PullRequestsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListPullRequestsRequest,
    ListPullRequestsResponse
  >[]
) {
  let request: ListPullRequestsRequest;
  let response: ListPullRequestsResponse;

  try {
    request = ListPullRequestsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListPullRequestsRequest,
      ListPullRequestsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListPullRequests(ctx, inputReq);
    });
  } else {
    response = await service.ListPullRequests(ctx, request!);
  }

  return Buffer.from(ListPullRequestsResponse.toBinary(response));
}

async function handlePullRequestsAPIStreamPullRequestContentProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PullRequestsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    StreamPullRequestContentRequest,
    StreamPullRequestContentResponse
  >[]
) {
  let request: StreamPullRequestContentRequest;
  let response: StreamPullRequestContentResponse;

  try {
    request = StreamPullRequestContentRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      StreamPullRequestContentRequest,
      StreamPullRequestContentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.StreamPullRequestContent(ctx, inputReq);
    });
  } else {
    response = await service.StreamPullRequestContent(ctx, request!);
  }

  return Buffer.from(StreamPullRequestContentResponse.toBinary(response));
}
