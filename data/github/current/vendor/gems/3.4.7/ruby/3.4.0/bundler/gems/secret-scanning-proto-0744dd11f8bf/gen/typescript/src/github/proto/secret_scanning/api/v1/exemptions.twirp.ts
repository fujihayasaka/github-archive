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
  GetExemptionRequest,
  GetExemptionResponse,
  GetExemptionsRequest,
  GetExemptionsResponse,
} from "./exemptions";

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

export interface ExemptionsAPIClient {
  GetExemption(request: GetExemptionRequest): Promise<GetExemptionResponse>;
  GetExemptions(request: GetExemptionsRequest): Promise<GetExemptionsResponse>;
}

export class ExemptionsAPIClientJSON implements ExemptionsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetExemption.bind(this);
    this.GetExemptions.bind(this);
  }
  GetExemption(request: GetExemptionRequest): Promise<GetExemptionResponse> {
    const data = GetExemptionRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.ExemptionsAPI",
      "GetExemption",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetExemptionResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetExemptions(request: GetExemptionsRequest): Promise<GetExemptionsResponse> {
    const data = GetExemptionsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.ExemptionsAPI",
      "GetExemptions",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetExemptionsResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class ExemptionsAPIClientProtobuf implements ExemptionsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetExemption.bind(this);
    this.GetExemptions.bind(this);
  }
  GetExemption(request: GetExemptionRequest): Promise<GetExemptionResponse> {
    const data = GetExemptionRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.ExemptionsAPI",
      "GetExemption",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetExemptionResponse.fromBinary(data as Uint8Array)
    );
  }

  GetExemptions(request: GetExemptionsRequest): Promise<GetExemptionsResponse> {
    const data = GetExemptionsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.ExemptionsAPI",
      "GetExemptions",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetExemptionsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface ExemptionsAPITwirp<T extends TwirpContext = TwirpContext> {
  GetExemption(
    ctx: T,
    request: GetExemptionRequest
  ): Promise<GetExemptionResponse>;
  GetExemptions(
    ctx: T,
    request: GetExemptionsRequest
  ): Promise<GetExemptionsResponse>;
}

export enum ExemptionsAPIMethod {
  GetExemption = "GetExemption",
  GetExemptions = "GetExemptions",
}

export const ExemptionsAPIMethodList = [
  ExemptionsAPIMethod.GetExemption,
  ExemptionsAPIMethod.GetExemptions,
];

export function createExemptionsAPIServer<
  T extends TwirpContext = TwirpContext
>(service: ExemptionsAPITwirp<T>) {
  return new TwirpServer<ExemptionsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "ExemptionsAPI",
    methodList: ExemptionsAPIMethodList,
    matchRoute: matchExemptionsAPIRoute,
  });
}

function matchExemptionsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetExemption":
      return async (
        ctx: T,
        service: ExemptionsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetExemptionRequest,
          GetExemptionResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetExemption" };
        await events.onMatch(ctx);
        return handleExemptionsAPIGetExemptionRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetExemptions":
      return async (
        ctx: T,
        service: ExemptionsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetExemptionsRequest,
          GetExemptionsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetExemptions" };
        await events.onMatch(ctx);
        return handleExemptionsAPIGetExemptionsRequest(
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

function handleExemptionsAPIGetExemptionRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ExemptionsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetExemptionRequest, GetExemptionResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleExemptionsAPIGetExemptionJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleExemptionsAPIGetExemptionProtobuf<T>(
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

function handleExemptionsAPIGetExemptionsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ExemptionsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetExemptionsRequest, GetExemptionsResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleExemptionsAPIGetExemptionsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleExemptionsAPIGetExemptionsProtobuf<T>(
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
async function handleExemptionsAPIGetExemptionJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ExemptionsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetExemptionRequest, GetExemptionResponse>[]
) {
  let request: GetExemptionRequest;
  let response: GetExemptionResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetExemptionRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetExemptionRequest,
      GetExemptionResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetExemption(ctx, inputReq);
    });
  } else {
    response = await service.GetExemption(ctx, request!);
  }

  return JSON.stringify(
    GetExemptionResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleExemptionsAPIGetExemptionsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ExemptionsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetExemptionsRequest, GetExemptionsResponse>[]
) {
  let request: GetExemptionsRequest;
  let response: GetExemptionsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetExemptionsRequest.fromJson(body, {
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
      GetExemptionsRequest,
      GetExemptionsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetExemptions(ctx, inputReq);
    });
  } else {
    response = await service.GetExemptions(ctx, request!);
  }

  return JSON.stringify(
    GetExemptionsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleExemptionsAPIGetExemptionProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ExemptionsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetExemptionRequest, GetExemptionResponse>[]
) {
  let request: GetExemptionRequest;
  let response: GetExemptionResponse;

  try {
    request = GetExemptionRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetExemptionRequest,
      GetExemptionResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetExemption(ctx, inputReq);
    });
  } else {
    response = await service.GetExemption(ctx, request!);
  }

  return Buffer.from(GetExemptionResponse.toBinary(response));
}

async function handleExemptionsAPIGetExemptionsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ExemptionsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetExemptionsRequest, GetExemptionsResponse>[]
) {
  let request: GetExemptionsRequest;
  let response: GetExemptionsResponse;

  try {
    request = GetExemptionsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetExemptionsRequest,
      GetExemptionsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetExemptions(ctx, inputReq);
    });
  } else {
    response = await service.GetExemptions(ctx, request!);
  }

  return Buffer.from(GetExemptionsResponse.toBinary(response));
}
