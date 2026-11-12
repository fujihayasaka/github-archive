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
  GetLatestRepositoryScansRequest,
  GetLatestRepositoryScansResponse,
} from "./scan_status_api";

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

export interface ScanStatusAPIClient {
  GetLatestRepositoryScans(
    request: GetLatestRepositoryScansRequest
  ): Promise<GetLatestRepositoryScansResponse>;
}

export class ScanStatusAPIClientJSON implements ScanStatusAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetLatestRepositoryScans.bind(this);
  }
  GetLatestRepositoryScans(
    request: GetLatestRepositoryScansRequest
  ): Promise<GetLatestRepositoryScansResponse> {
    const data = GetLatestRepositoryScansRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.ScanStatusAPI",
      "GetLatestRepositoryScans",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetLatestRepositoryScansResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class ScanStatusAPIClientProtobuf implements ScanStatusAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetLatestRepositoryScans.bind(this);
  }
  GetLatestRepositoryScans(
    request: GetLatestRepositoryScansRequest
  ): Promise<GetLatestRepositoryScansResponse> {
    const data = GetLatestRepositoryScansRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.ScanStatusAPI",
      "GetLatestRepositoryScans",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetLatestRepositoryScansResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface ScanStatusAPITwirp<T extends TwirpContext = TwirpContext> {
  GetLatestRepositoryScans(
    ctx: T,
    request: GetLatestRepositoryScansRequest
  ): Promise<GetLatestRepositoryScansResponse>;
}

export enum ScanStatusAPIMethod {
  GetLatestRepositoryScans = "GetLatestRepositoryScans",
}

export const ScanStatusAPIMethodList = [
  ScanStatusAPIMethod.GetLatestRepositoryScans,
];

export function createScanStatusAPIServer<
  T extends TwirpContext = TwirpContext
>(service: ScanStatusAPITwirp<T>) {
  return new TwirpServer<ScanStatusAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "ScanStatusAPI",
    methodList: ScanStatusAPIMethodList,
    matchRoute: matchScanStatusAPIRoute,
  });
}

function matchScanStatusAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetLatestRepositoryScans":
      return async (
        ctx: T,
        service: ScanStatusAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetLatestRepositoryScansRequest,
          GetLatestRepositoryScansResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetLatestRepositoryScans" };
        await events.onMatch(ctx);
        return handleScanStatusAPIGetLatestRepositoryScansRequest(
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

function handleScanStatusAPIGetLatestRepositoryScansRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScanStatusAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetLatestRepositoryScansRequest,
    GetLatestRepositoryScansResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleScanStatusAPIGetLatestRepositoryScansJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleScanStatusAPIGetLatestRepositoryScansProtobuf<T>(
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
async function handleScanStatusAPIGetLatestRepositoryScansJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScanStatusAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetLatestRepositoryScansRequest,
    GetLatestRepositoryScansResponse
  >[]
) {
  let request: GetLatestRepositoryScansRequest;
  let response: GetLatestRepositoryScansResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetLatestRepositoryScansRequest.fromJson(body, {
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
      GetLatestRepositoryScansRequest,
      GetLatestRepositoryScansResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetLatestRepositoryScans(ctx, inputReq);
    });
  } else {
    response = await service.GetLatestRepositoryScans(ctx, request!);
  }

  return JSON.stringify(
    GetLatestRepositoryScansResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleScanStatusAPIGetLatestRepositoryScansProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: ScanStatusAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetLatestRepositoryScansRequest,
    GetLatestRepositoryScansResponse
  >[]
) {
  let request: GetLatestRepositoryScansRequest;
  let response: GetLatestRepositoryScansResponse;

  try {
    request = GetLatestRepositoryScansRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetLatestRepositoryScansRequest,
      GetLatestRepositoryScansResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetLatestRepositoryScans(ctx, inputReq);
    });
  } else {
    response = await service.GetLatestRepositoryScans(ctx, request!);
  }

  return Buffer.from(GetLatestRepositoryScansResponse.toBinary(response));
}
