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
  GetWorkflowRunByCheckSuiteRequest,
  GetWorkflowRunByCheckSuiteResponse,
} from "./actionlogs_api";

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

export interface ActionlogsAPIClient {
  GetWorkflowRunByCheckSuite(
    request: GetWorkflowRunByCheckSuiteRequest
  ): Promise<GetWorkflowRunByCheckSuiteResponse>;
}

export class ActionlogsAPIClientJSON implements ActionlogsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetWorkflowRunByCheckSuite.bind(this);
  }
  GetWorkflowRunByCheckSuite(
    request: GetWorkflowRunByCheckSuiteRequest
  ): Promise<GetWorkflowRunByCheckSuiteResponse> {
    const data = GetWorkflowRunByCheckSuiteRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.actionlogs.v1.ActionlogsAPI",
      "GetWorkflowRunByCheckSuite",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetWorkflowRunByCheckSuiteResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class ActionlogsAPIClientProtobuf implements ActionlogsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetWorkflowRunByCheckSuite.bind(this);
  }
  GetWorkflowRunByCheckSuite(
    request: GetWorkflowRunByCheckSuiteRequest
  ): Promise<GetWorkflowRunByCheckSuiteResponse> {
    const data = GetWorkflowRunByCheckSuiteRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.actionlogs.v1.ActionlogsAPI",
      "GetWorkflowRunByCheckSuite",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetWorkflowRunByCheckSuiteResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface ActionlogsAPITwirp<T extends TwirpContext = TwirpContext> {
  GetWorkflowRunByCheckSuite(
    ctx: T,
    request: GetWorkflowRunByCheckSuiteRequest
  ): Promise<GetWorkflowRunByCheckSuiteResponse>;
}

export enum ActionlogsAPIMethod {
  GetWorkflowRunByCheckSuite = "GetWorkflowRunByCheckSuite",
}

export const ActionlogsAPIMethodList = [
  ActionlogsAPIMethod.GetWorkflowRunByCheckSuite,
];

export function createActionlogsAPIServer<
  T extends TwirpContext = TwirpContext
>(service: ActionlogsAPITwirp<T>) {
  return new TwirpServer<ActionlogsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.actionlogs.v1",
    serviceName: "ActionlogsAPI",
    methodList: ActionlogsAPIMethodList,
    matchRoute: matchActionlogsAPIRoute,
  });
}

function matchActionlogsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetWorkflowRunByCheckSuite":
      return async (
        ctx: T,
        service: ActionlogsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetWorkflowRunByCheckSuiteRequest,
          GetWorkflowRunByCheckSuiteResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetWorkflowRunByCheckSuite" };
        await events.onMatch(ctx);
        return handleActionlogsAPIGetWorkflowRunByCheckSuiteRequest(
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

function handleActionlogsAPIGetWorkflowRunByCheckSuiteRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ActionlogsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetWorkflowRunByCheckSuiteRequest,
    GetWorkflowRunByCheckSuiteResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleActionlogsAPIGetWorkflowRunByCheckSuiteJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleActionlogsAPIGetWorkflowRunByCheckSuiteProtobuf<T>(
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
async function handleActionlogsAPIGetWorkflowRunByCheckSuiteJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ActionlogsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetWorkflowRunByCheckSuiteRequest,
    GetWorkflowRunByCheckSuiteResponse
  >[]
) {
  let request: GetWorkflowRunByCheckSuiteRequest;
  let response: GetWorkflowRunByCheckSuiteResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetWorkflowRunByCheckSuiteRequest.fromJson(body, {
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
      GetWorkflowRunByCheckSuiteRequest,
      GetWorkflowRunByCheckSuiteResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetWorkflowRunByCheckSuite(ctx, inputReq);
    });
  } else {
    response = await service.GetWorkflowRunByCheckSuite(ctx, request!);
  }

  return JSON.stringify(
    GetWorkflowRunByCheckSuiteResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleActionlogsAPIGetWorkflowRunByCheckSuiteProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ActionlogsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetWorkflowRunByCheckSuiteRequest,
    GetWorkflowRunByCheckSuiteResponse
  >[]
) {
  let request: GetWorkflowRunByCheckSuiteRequest;
  let response: GetWorkflowRunByCheckSuiteResponse;

  try {
    request = GetWorkflowRunByCheckSuiteRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetWorkflowRunByCheckSuiteRequest,
      GetWorkflowRunByCheckSuiteResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetWorkflowRunByCheckSuite(ctx, inputReq);
    });
  } else {
    response = await service.GetWorkflowRunByCheckSuite(ctx, request!);
  }

  return Buffer.from(GetWorkflowRunByCheckSuiteResponse.toBinary(response));
}
