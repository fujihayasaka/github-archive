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
  GetIssueRequest,
  GetIssueResponse,
  GetIssueBodyHistoryRequest,
  GetIssueBodyHistoryResponse,
  GetIssueTitleHistoryRequest,
  GetIssueTitleHistoryResponse,
  GetIssueCommentRequest,
  GetIssueCommentResponse,
  GetIssueCommentHistoryRequest,
  GetIssueCommentHistoryResponse,
  ListIssuesRequest,
  ListIssuesResponse,
  ListIssueCommentsRequest,
  ListIssueCommentsResponse,
} from "./issues_api";

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

export interface IssueAPIClient {
  GetIssue(request: GetIssueRequest): Promise<GetIssueResponse>;
  GetIssueBodyHistory(
    request: GetIssueBodyHistoryRequest
  ): Promise<GetIssueBodyHistoryResponse>;
  GetIssueTitleHistory(
    request: GetIssueTitleHistoryRequest
  ): Promise<GetIssueTitleHistoryResponse>;
  GetIssueComment(
    request: GetIssueCommentRequest
  ): Promise<GetIssueCommentResponse>;
  GetIssueCommentHistory(
    request: GetIssueCommentHistoryRequest
  ): Promise<GetIssueCommentHistoryResponse>;
  ListIssues(request: ListIssuesRequest): Promise<ListIssuesResponse>;
  ListIssueComments(
    request: ListIssueCommentsRequest
  ): Promise<ListIssueCommentsResponse>;
}

export class IssueAPIClientJSON implements IssueAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetIssue.bind(this);
    this.GetIssueBodyHistory.bind(this);
    this.GetIssueTitleHistory.bind(this);
    this.GetIssueComment.bind(this);
    this.GetIssueCommentHistory.bind(this);
    this.ListIssues.bind(this);
    this.ListIssueComments.bind(this);
  }
  GetIssue(request: GetIssueRequest): Promise<GetIssueResponse> {
    const data = GetIssueRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssue",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetIssueResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetIssueBodyHistory(
    request: GetIssueBodyHistoryRequest
  ): Promise<GetIssueBodyHistoryResponse> {
    const data = GetIssueBodyHistoryRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueBodyHistory",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetIssueBodyHistoryResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetIssueTitleHistory(
    request: GetIssueTitleHistoryRequest
  ): Promise<GetIssueTitleHistoryResponse> {
    const data = GetIssueTitleHistoryRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueTitleHistory",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetIssueTitleHistoryResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetIssueComment(
    request: GetIssueCommentRequest
  ): Promise<GetIssueCommentResponse> {
    const data = GetIssueCommentRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueComment",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetIssueCommentResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetIssueCommentHistory(
    request: GetIssueCommentHistoryRequest
  ): Promise<GetIssueCommentHistoryResponse> {
    const data = GetIssueCommentHistoryRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueCommentHistory",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetIssueCommentHistoryResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  ListIssues(request: ListIssuesRequest): Promise<ListIssuesResponse> {
    const data = ListIssuesRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "ListIssues",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListIssuesResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  ListIssueComments(
    request: ListIssueCommentsRequest
  ): Promise<ListIssueCommentsResponse> {
    const data = ListIssueCommentsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "ListIssueComments",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListIssueCommentsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class IssueAPIClientProtobuf implements IssueAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetIssue.bind(this);
    this.GetIssueBodyHistory.bind(this);
    this.GetIssueTitleHistory.bind(this);
    this.GetIssueComment.bind(this);
    this.GetIssueCommentHistory.bind(this);
    this.ListIssues.bind(this);
    this.ListIssueComments.bind(this);
  }
  GetIssue(request: GetIssueRequest): Promise<GetIssueResponse> {
    const data = GetIssueRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssue",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetIssueResponse.fromBinary(data as Uint8Array)
    );
  }

  GetIssueBodyHistory(
    request: GetIssueBodyHistoryRequest
  ): Promise<GetIssueBodyHistoryResponse> {
    const data = GetIssueBodyHistoryRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueBodyHistory",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetIssueBodyHistoryResponse.fromBinary(data as Uint8Array)
    );
  }

  GetIssueTitleHistory(
    request: GetIssueTitleHistoryRequest
  ): Promise<GetIssueTitleHistoryResponse> {
    const data = GetIssueTitleHistoryRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueTitleHistory",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetIssueTitleHistoryResponse.fromBinary(data as Uint8Array)
    );
  }

  GetIssueComment(
    request: GetIssueCommentRequest
  ): Promise<GetIssueCommentResponse> {
    const data = GetIssueCommentRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueComment",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetIssueCommentResponse.fromBinary(data as Uint8Array)
    );
  }

  GetIssueCommentHistory(
    request: GetIssueCommentHistoryRequest
  ): Promise<GetIssueCommentHistoryResponse> {
    const data = GetIssueCommentHistoryRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "GetIssueCommentHistory",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetIssueCommentHistoryResponse.fromBinary(data as Uint8Array)
    );
  }

  ListIssues(request: ListIssuesRequest): Promise<ListIssuesResponse> {
    const data = ListIssuesRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "ListIssues",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListIssuesResponse.fromBinary(data as Uint8Array)
    );
  }

  ListIssueComments(
    request: ListIssueCommentsRequest
  ): Promise<ListIssueCommentsResponse> {
    const data = ListIssueCommentsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.issues.v1.IssueAPI",
      "ListIssueComments",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListIssueCommentsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface IssueAPITwirp<T extends TwirpContext = TwirpContext> {
  GetIssue(ctx: T, request: GetIssueRequest): Promise<GetIssueResponse>;
  GetIssueBodyHistory(
    ctx: T,
    request: GetIssueBodyHistoryRequest
  ): Promise<GetIssueBodyHistoryResponse>;
  GetIssueTitleHistory(
    ctx: T,
    request: GetIssueTitleHistoryRequest
  ): Promise<GetIssueTitleHistoryResponse>;
  GetIssueComment(
    ctx: T,
    request: GetIssueCommentRequest
  ): Promise<GetIssueCommentResponse>;
  GetIssueCommentHistory(
    ctx: T,
    request: GetIssueCommentHistoryRequest
  ): Promise<GetIssueCommentHistoryResponse>;
  ListIssues(ctx: T, request: ListIssuesRequest): Promise<ListIssuesResponse>;
  ListIssueComments(
    ctx: T,
    request: ListIssueCommentsRequest
  ): Promise<ListIssueCommentsResponse>;
}

export enum IssueAPIMethod {
  GetIssue = "GetIssue",
  GetIssueBodyHistory = "GetIssueBodyHistory",
  GetIssueTitleHistory = "GetIssueTitleHistory",
  GetIssueComment = "GetIssueComment",
  GetIssueCommentHistory = "GetIssueCommentHistory",
  ListIssues = "ListIssues",
  ListIssueComments = "ListIssueComments",
}

export const IssueAPIMethodList = [
  IssueAPIMethod.GetIssue,
  IssueAPIMethod.GetIssueBodyHistory,
  IssueAPIMethod.GetIssueTitleHistory,
  IssueAPIMethod.GetIssueComment,
  IssueAPIMethod.GetIssueCommentHistory,
  IssueAPIMethod.ListIssues,
  IssueAPIMethod.ListIssueComments,
];

export function createIssueAPIServer<T extends TwirpContext = TwirpContext>(
  service: IssueAPITwirp<T>
) {
  return new TwirpServer<IssueAPITwirp, T>({
    service,
    packageName: "github.secretscanning.issues.v1",
    serviceName: "IssueAPI",
    methodList: IssueAPIMethodList,
    matchRoute: matchIssueAPIRoute,
  });
}

function matchIssueAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetIssue":
      return async (
        ctx: T,
        service: IssueAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, GetIssueRequest, GetIssueResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "GetIssue" };
        await events.onMatch(ctx);
        return handleIssueAPIGetIssueRequest(ctx, service, data, interceptors);
      };
    case "GetIssueBodyHistory":
      return async (
        ctx: T,
        service: IssueAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetIssueBodyHistoryRequest,
          GetIssueBodyHistoryResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetIssueBodyHistory" };
        await events.onMatch(ctx);
        return handleIssueAPIGetIssueBodyHistoryRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetIssueTitleHistory":
      return async (
        ctx: T,
        service: IssueAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetIssueTitleHistoryRequest,
          GetIssueTitleHistoryResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetIssueTitleHistory" };
        await events.onMatch(ctx);
        return handleIssueAPIGetIssueTitleHistoryRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetIssueComment":
      return async (
        ctx: T,
        service: IssueAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetIssueCommentRequest,
          GetIssueCommentResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetIssueComment" };
        await events.onMatch(ctx);
        return handleIssueAPIGetIssueCommentRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetIssueCommentHistory":
      return async (
        ctx: T,
        service: IssueAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetIssueCommentHistoryRequest,
          GetIssueCommentHistoryResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetIssueCommentHistory" };
        await events.onMatch(ctx);
        return handleIssueAPIGetIssueCommentHistoryRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ListIssues":
      return async (
        ctx: T,
        service: IssueAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, ListIssuesRequest, ListIssuesResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "ListIssues" };
        await events.onMatch(ctx);
        return handleIssueAPIListIssuesRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ListIssueComments":
      return async (
        ctx: T,
        service: IssueAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ListIssueCommentsRequest,
          ListIssueCommentsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ListIssueComments" };
        await events.onMatch(ctx);
        return handleIssueAPIListIssueCommentsRequest(
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

function handleIssueAPIGetIssueRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetIssueRequest, GetIssueResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleIssueAPIGetIssueJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleIssueAPIGetIssueProtobuf<T>(
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

function handleIssueAPIGetIssueBodyHistoryRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueBodyHistoryRequest,
    GetIssueBodyHistoryResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleIssueAPIGetIssueBodyHistoryJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleIssueAPIGetIssueBodyHistoryProtobuf<T>(
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

function handleIssueAPIGetIssueTitleHistoryRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueTitleHistoryRequest,
    GetIssueTitleHistoryResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleIssueAPIGetIssueTitleHistoryJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleIssueAPIGetIssueTitleHistoryProtobuf<T>(
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

function handleIssueAPIGetIssueCommentRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueCommentRequest,
    GetIssueCommentResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleIssueAPIGetIssueCommentJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleIssueAPIGetIssueCommentProtobuf<T>(
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

function handleIssueAPIGetIssueCommentHistoryRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueCommentHistoryRequest,
    GetIssueCommentHistoryResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleIssueAPIGetIssueCommentHistoryJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleIssueAPIGetIssueCommentHistoryProtobuf<T>(
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

function handleIssueAPIListIssuesRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ListIssuesRequest, ListIssuesResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleIssueAPIListIssuesJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleIssueAPIListIssuesProtobuf<T>(
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

function handleIssueAPIListIssueCommentsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListIssueCommentsRequest,
    ListIssueCommentsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleIssueAPIListIssueCommentsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleIssueAPIListIssueCommentsProtobuf<T>(
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
async function handleIssueAPIGetIssueJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetIssueRequest, GetIssueResponse>[]
) {
  let request: GetIssueRequest;
  let response: GetIssueResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetIssueRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetIssueRequest,
      GetIssueResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssue(ctx, inputReq);
    });
  } else {
    response = await service.GetIssue(ctx, request!);
  }

  return JSON.stringify(
    GetIssueResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleIssueAPIGetIssueBodyHistoryJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueBodyHistoryRequest,
    GetIssueBodyHistoryResponse
  >[]
) {
  let request: GetIssueBodyHistoryRequest;
  let response: GetIssueBodyHistoryResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetIssueBodyHistoryRequest.fromJson(body, {
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
      GetIssueBodyHistoryRequest,
      GetIssueBodyHistoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueBodyHistory(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueBodyHistory(ctx, request!);
  }

  return JSON.stringify(
    GetIssueBodyHistoryResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleIssueAPIGetIssueTitleHistoryJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueTitleHistoryRequest,
    GetIssueTitleHistoryResponse
  >[]
) {
  let request: GetIssueTitleHistoryRequest;
  let response: GetIssueTitleHistoryResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetIssueTitleHistoryRequest.fromJson(body, {
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
      GetIssueTitleHistoryRequest,
      GetIssueTitleHistoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueTitleHistory(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueTitleHistory(ctx, request!);
  }

  return JSON.stringify(
    GetIssueTitleHistoryResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleIssueAPIGetIssueCommentJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueCommentRequest,
    GetIssueCommentResponse
  >[]
) {
  let request: GetIssueCommentRequest;
  let response: GetIssueCommentResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetIssueCommentRequest.fromJson(body, {
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
      GetIssueCommentRequest,
      GetIssueCommentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueComment(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueComment(ctx, request!);
  }

  return JSON.stringify(
    GetIssueCommentResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleIssueAPIGetIssueCommentHistoryJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueCommentHistoryRequest,
    GetIssueCommentHistoryResponse
  >[]
) {
  let request: GetIssueCommentHistoryRequest;
  let response: GetIssueCommentHistoryResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetIssueCommentHistoryRequest.fromJson(body, {
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
      GetIssueCommentHistoryRequest,
      GetIssueCommentHistoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueCommentHistory(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueCommentHistory(ctx, request!);
  }

  return JSON.stringify(
    GetIssueCommentHistoryResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleIssueAPIListIssuesJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ListIssuesRequest, ListIssuesResponse>[]
) {
  let request: ListIssuesRequest;
  let response: ListIssuesResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListIssuesRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListIssuesRequest,
      ListIssuesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListIssues(ctx, inputReq);
    });
  } else {
    response = await service.ListIssues(ctx, request!);
  }

  return JSON.stringify(
    ListIssuesResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleIssueAPIListIssueCommentsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListIssueCommentsRequest,
    ListIssueCommentsResponse
  >[]
) {
  let request: ListIssueCommentsRequest;
  let response: ListIssueCommentsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListIssueCommentsRequest.fromJson(body, {
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
      ListIssueCommentsRequest,
      ListIssueCommentsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListIssueComments(ctx, inputReq);
    });
  } else {
    response = await service.ListIssueComments(ctx, request!);
  }

  return JSON.stringify(
    ListIssueCommentsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleIssueAPIGetIssueProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetIssueRequest, GetIssueResponse>[]
) {
  let request: GetIssueRequest;
  let response: GetIssueResponse;

  try {
    request = GetIssueRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetIssueRequest,
      GetIssueResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssue(ctx, inputReq);
    });
  } else {
    response = await service.GetIssue(ctx, request!);
  }

  return Buffer.from(GetIssueResponse.toBinary(response));
}

async function handleIssueAPIGetIssueBodyHistoryProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueBodyHistoryRequest,
    GetIssueBodyHistoryResponse
  >[]
) {
  let request: GetIssueBodyHistoryRequest;
  let response: GetIssueBodyHistoryResponse;

  try {
    request = GetIssueBodyHistoryRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetIssueBodyHistoryRequest,
      GetIssueBodyHistoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueBodyHistory(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueBodyHistory(ctx, request!);
  }

  return Buffer.from(GetIssueBodyHistoryResponse.toBinary(response));
}

async function handleIssueAPIGetIssueTitleHistoryProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueTitleHistoryRequest,
    GetIssueTitleHistoryResponse
  >[]
) {
  let request: GetIssueTitleHistoryRequest;
  let response: GetIssueTitleHistoryResponse;

  try {
    request = GetIssueTitleHistoryRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetIssueTitleHistoryRequest,
      GetIssueTitleHistoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueTitleHistory(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueTitleHistory(ctx, request!);
  }

  return Buffer.from(GetIssueTitleHistoryResponse.toBinary(response));
}

async function handleIssueAPIGetIssueCommentProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueCommentRequest,
    GetIssueCommentResponse
  >[]
) {
  let request: GetIssueCommentRequest;
  let response: GetIssueCommentResponse;

  try {
    request = GetIssueCommentRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetIssueCommentRequest,
      GetIssueCommentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueComment(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueComment(ctx, request!);
  }

  return Buffer.from(GetIssueCommentResponse.toBinary(response));
}

async function handleIssueAPIGetIssueCommentHistoryProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetIssueCommentHistoryRequest,
    GetIssueCommentHistoryResponse
  >[]
) {
  let request: GetIssueCommentHistoryRequest;
  let response: GetIssueCommentHistoryResponse;

  try {
    request = GetIssueCommentHistoryRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetIssueCommentHistoryRequest,
      GetIssueCommentHistoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetIssueCommentHistory(ctx, inputReq);
    });
  } else {
    response = await service.GetIssueCommentHistory(ctx, request!);
  }

  return Buffer.from(GetIssueCommentHistoryResponse.toBinary(response));
}

async function handleIssueAPIListIssuesProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ListIssuesRequest, ListIssuesResponse>[]
) {
  let request: ListIssuesRequest;
  let response: ListIssuesResponse;

  try {
    request = ListIssuesRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListIssuesRequest,
      ListIssuesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListIssues(ctx, inputReq);
    });
  } else {
    response = await service.ListIssues(ctx, request!);
  }

  return Buffer.from(ListIssuesResponse.toBinary(response));
}

async function handleIssueAPIListIssueCommentsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: IssueAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListIssueCommentsRequest,
    ListIssueCommentsResponse
  >[]
) {
  let request: ListIssueCommentsRequest;
  let response: ListIssueCommentsResponse;

  try {
    request = ListIssueCommentsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListIssueCommentsRequest,
      ListIssueCommentsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListIssueComments(ctx, inputReq);
    });
  } else {
    response = await service.ListIssueComments(ctx, request!);
  }

  return Buffer.from(ListIssueCommentsResponse.toBinary(response));
}
