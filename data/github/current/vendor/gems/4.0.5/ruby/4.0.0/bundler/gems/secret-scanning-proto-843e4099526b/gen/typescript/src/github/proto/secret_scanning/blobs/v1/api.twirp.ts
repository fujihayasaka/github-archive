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
import { GetLocationsRequest, GetLocationsResponse } from "./api";

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

export interface BlobsAPIClient {
  GetLocations(request: GetLocationsRequest): Promise<GetLocationsResponse>;
}

export class BlobsAPIClientJSON implements BlobsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetLocations.bind(this);
  }
  GetLocations(request: GetLocationsRequest): Promise<GetLocationsResponse> {
    const data = GetLocationsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.blobs.v1.BlobsAPI",
      "GetLocations",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetLocationsResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class BlobsAPIClientProtobuf implements BlobsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetLocations.bind(this);
  }
  GetLocations(request: GetLocationsRequest): Promise<GetLocationsResponse> {
    const data = GetLocationsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.blobs.v1.BlobsAPI",
      "GetLocations",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetLocationsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface BlobsAPITwirp<T extends TwirpContext = TwirpContext> {
  GetLocations(
    ctx: T,
    request: GetLocationsRequest
  ): Promise<GetLocationsResponse>;
}

export enum BlobsAPIMethod {
  GetLocations = "GetLocations",
}

export const BlobsAPIMethodList = [BlobsAPIMethod.GetLocations];

export function createBlobsAPIServer<T extends TwirpContext = TwirpContext>(
  service: BlobsAPITwirp<T>
) {
  return new TwirpServer<BlobsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.blobs.v1",
    serviceName: "BlobsAPI",
    methodList: BlobsAPIMethodList,
    matchRoute: matchBlobsAPIRoute,
  });
}

function matchBlobsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetLocations":
      return async (
        ctx: T,
        service: BlobsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetLocationsRequest,
          GetLocationsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetLocations" };
        await events.onMatch(ctx);
        return handleBlobsAPIGetLocationsRequest(
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

function handleBlobsAPIGetLocationsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BlobsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetLocationsRequest, GetLocationsResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleBlobsAPIGetLocationsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleBlobsAPIGetLocationsProtobuf<T>(
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
async function handleBlobsAPIGetLocationsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BlobsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetLocationsRequest, GetLocationsResponse>[]
) {
  let request: GetLocationsRequest;
  let response: GetLocationsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetLocationsRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetLocationsRequest,
      GetLocationsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetLocations(ctx, inputReq);
    });
  } else {
    response = await service.GetLocations(ctx, request!);
  }

  return JSON.stringify(
    GetLocationsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleBlobsAPIGetLocationsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BlobsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetLocationsRequest, GetLocationsResponse>[]
) {
  let request: GetLocationsRequest;
  let response: GetLocationsResponse;

  try {
    request = GetLocationsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetLocationsRequest,
      GetLocationsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetLocations(ctx, inputReq);
    });
  } else {
    response = await service.GetLocations(ctx, request!);
  }

  return Buffer.from(GetLocationsResponse.toBinary(response));
}
