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
  ListDiscussionsRequest,
  ListDiscussionsResponse,
  StreamDiscussionContentRequest,
  StreamDiscussionContentResponse,
} from "./discussions_api";

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

export interface DiscussionAPIClient {
  ListDiscussions(
    request: ListDiscussionsRequest
  ): Promise<ListDiscussionsResponse>;
  StreamDiscussionContent(
    request: StreamDiscussionContentRequest
  ): Promise<StreamDiscussionContentResponse>;
}

export class DiscussionAPIClientJSON implements DiscussionAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ListDiscussions.bind(this);
    this.StreamDiscussionContent.bind(this);
  }
  ListDiscussions(
    request: ListDiscussionsRequest
  ): Promise<ListDiscussionsResponse> {
    const data = ListDiscussionsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.discussions.v1.DiscussionAPI",
      "ListDiscussions",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListDiscussionsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  StreamDiscussionContent(
    request: StreamDiscussionContentRequest
  ): Promise<StreamDiscussionContentResponse> {
    const data = StreamDiscussionContentRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.discussions.v1.DiscussionAPI",
      "StreamDiscussionContent",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      StreamDiscussionContentResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class DiscussionAPIClientProtobuf implements DiscussionAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ListDiscussions.bind(this);
    this.StreamDiscussionContent.bind(this);
  }
  ListDiscussions(
    request: ListDiscussionsRequest
  ): Promise<ListDiscussionsResponse> {
    const data = ListDiscussionsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.discussions.v1.DiscussionAPI",
      "ListDiscussions",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListDiscussionsResponse.fromBinary(data as Uint8Array)
    );
  }

  StreamDiscussionContent(
    request: StreamDiscussionContentRequest
  ): Promise<StreamDiscussionContentResponse> {
    const data = StreamDiscussionContentRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.discussions.v1.DiscussionAPI",
      "StreamDiscussionContent",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      StreamDiscussionContentResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface DiscussionAPITwirp<T extends TwirpContext = TwirpContext> {
  ListDiscussions(
    ctx: T,
    request: ListDiscussionsRequest
  ): Promise<ListDiscussionsResponse>;
  StreamDiscussionContent(
    ctx: T,
    request: StreamDiscussionContentRequest
  ): Promise<StreamDiscussionContentResponse>;
}

export enum DiscussionAPIMethod {
  ListDiscussions = "ListDiscussions",
  StreamDiscussionContent = "StreamDiscussionContent",
}

export const DiscussionAPIMethodList = [
  DiscussionAPIMethod.ListDiscussions,
  DiscussionAPIMethod.StreamDiscussionContent,
];

export function createDiscussionAPIServer<
  T extends TwirpContext = TwirpContext
>(service: DiscussionAPITwirp<T>) {
  return new TwirpServer<DiscussionAPITwirp, T>({
    service,
    packageName: "github.secretscanning.discussions.v1",
    serviceName: "DiscussionAPI",
    methodList: DiscussionAPIMethodList,
    matchRoute: matchDiscussionAPIRoute,
  });
}

function matchDiscussionAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "ListDiscussions":
      return async (
        ctx: T,
        service: DiscussionAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ListDiscussionsRequest,
          ListDiscussionsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ListDiscussions" };
        await events.onMatch(ctx);
        return handleDiscussionAPIListDiscussionsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "StreamDiscussionContent":
      return async (
        ctx: T,
        service: DiscussionAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          StreamDiscussionContentRequest,
          StreamDiscussionContentResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "StreamDiscussionContent" };
        await events.onMatch(ctx);
        return handleDiscussionAPIStreamDiscussionContentRequest(
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

function handleDiscussionAPIListDiscussionsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DiscussionAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListDiscussionsRequest,
    ListDiscussionsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleDiscussionAPIListDiscussionsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleDiscussionAPIListDiscussionsProtobuf<T>(
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

function handleDiscussionAPIStreamDiscussionContentRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DiscussionAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    StreamDiscussionContentRequest,
    StreamDiscussionContentResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleDiscussionAPIStreamDiscussionContentJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleDiscussionAPIStreamDiscussionContentProtobuf<T>(
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
async function handleDiscussionAPIListDiscussionsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DiscussionAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListDiscussionsRequest,
    ListDiscussionsResponse
  >[]
) {
  let request: ListDiscussionsRequest;
  let response: ListDiscussionsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListDiscussionsRequest.fromJson(body, {
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
      ListDiscussionsRequest,
      ListDiscussionsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListDiscussions(ctx, inputReq);
    });
  } else {
    response = await service.ListDiscussions(ctx, request!);
  }

  return JSON.stringify(
    ListDiscussionsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleDiscussionAPIStreamDiscussionContentJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DiscussionAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    StreamDiscussionContentRequest,
    StreamDiscussionContentResponse
  >[]
) {
  let request: StreamDiscussionContentRequest;
  let response: StreamDiscussionContentResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = StreamDiscussionContentRequest.fromJson(body, {
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
      StreamDiscussionContentRequest,
      StreamDiscussionContentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.StreamDiscussionContent(ctx, inputReq);
    });
  } else {
    response = await service.StreamDiscussionContent(ctx, request!);
  }

  return JSON.stringify(
    StreamDiscussionContentResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleDiscussionAPIListDiscussionsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DiscussionAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListDiscussionsRequest,
    ListDiscussionsResponse
  >[]
) {
  let request: ListDiscussionsRequest;
  let response: ListDiscussionsResponse;

  try {
    request = ListDiscussionsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListDiscussionsRequest,
      ListDiscussionsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListDiscussions(ctx, inputReq);
    });
  } else {
    response = await service.ListDiscussions(ctx, request!);
  }

  return Buffer.from(ListDiscussionsResponse.toBinary(response));
}

async function handleDiscussionAPIStreamDiscussionContentProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: DiscussionAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    StreamDiscussionContentRequest,
    StreamDiscussionContentResponse
  >[]
) {
  let request: StreamDiscussionContentRequest;
  let response: StreamDiscussionContentResponse;

  try {
    request = StreamDiscussionContentRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      StreamDiscussionContentRequest,
      StreamDiscussionContentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.StreamDiscussionContent(ctx, inputReq);
    });
  } else {
    response = await service.StreamDiscussionContent(ctx, request!);
  }

  return Buffer.from(StreamDiscussionContentResponse.toBinary(response));
}
