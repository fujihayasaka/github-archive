require_relative "../lib/nuget_importer"
require "addressable/uri"

class FakeNugetServer

  def initialize
  end

  # server replicates smaller catalog index than that of nuget

  def index
    {
      "commitId": "3d698852-eefb-48ed-8f55-9ee357540d20",
      "commitTimeStamp": "2017-10-31T23:33:17.0954363Z",
      "count": 3,
      "items": [
        {
          "@id": "#{address}/v3/catalog0/page0.json",
          "commitId": "3a4df280-3d86-458e-a713-4c91ca261fef",
          "commitTimeStamp": "2015-02-01T06:30:11.7477681Z",
          "count": 2
        },
        {
          "@id": "#{address}/v3/catalog0/page1.json",
          "commitId": "8bcd3cbf-74f0-47a2-a7ae-b7ecc50005d3",
          "commitTimeStamp": "2015-02-01T06:39:53.9553899Z",
          "count": 2
        },
        {
          "@id": "#{address}/v3/catalog0/page2.json",
          "commitId": "3a94eead-7619-46b6-a502-13d7a21d9a97",
          "commitTimeStamp": "2015-02-01T06:58:47.9532886Z",
          "count": 1
        }
      ],
    }
  end

  # pages of package data in our server replication of nuget server

  def page0
    {
      "@id": "#{address}/v3/catalog0/page0.json",
      "@type": "CatalogPage",
      "commitId": "00000000-0000-0000-0000-000000000000",
      "commitTimeStamp": "2015-02-01T06:30:11.7477681Z",
      "count": 2,
      "items": [
        {
          "@id": "#{address}/v3/catalog0/data/2015.02.01.06.22.45/adam.jsgenerator.1.1.0.json",
          "@type": "nuget:PackageDetails",
          "commitTimeStamp": "2015-02-01T06:22:45.8488496Z",
          "nuget:id": "Adam.JSGenerator",
          "nuget:version": "1.1.0",
          "commitId": "b3f4fc8a-7522-42a3-8fee-a91d5488c0b1"
        },
        {
          "@id": "#{address}/v3/catalog0/data/2015.02.01.06.22.45/agatha-rrsl.1.2.0.json",
          "@type": "nuget:PackageDetails",
          "commitTimeStamp": "2015-02-01T06:22:45.8488496Z",
          "nuget:id": "Agatha-rrsl",
          "nuget:version": "1.2.0",
          "commitId": "b3f4fc8a-7522-42a3-8fee-a91d5488c0b1"
        }
      ]
    }
  end

  def page1
    {
      "@id": "#{address}/v3/catalog0/page1.json",
      "@type": "CatalogPage",
      "commitId": "8bcd3cbf-74f0-47a2-a7ae-b7ecc50005d3",
      "commitTimeStamp": "2015-02-01T06:39:53.9553899Z",
      "count": 3,
      "items": [
        {
          "@id": "#{address}/v3/catalog0/data/2015.02.01.06.34.14/structuremap.2.6.2.json",
          "@type": "nuget:PackageDetails",
          "commitId": "e5421e4c-fb0a-4fc0-8246-65dd5d4fdd09",
          "commitTimeStamp": "2015-02-01T06:34:14.750674Z",
          "nuget:id": "structuremap",
          "nuget:version": "2.6.2"
        },
        {
          "@id": "#{address}/v3/catalog0/data/2015.02.01.06.33.04/elevate.0.1.0.json",
          "@type": "nuget:PackageDetails",
          "commitId": "fef2290b-3a1f-4f6c-ad7c-f9f36702c9e9",
          "commitTimeStamp": "2015-02-01T06:33:04.5000408Z",
          "nuget:id": "elevate",
          "nuget:version": "0.1.0"
        }
      ]
    }
  end

  def page2
    {
      "@id": "#{address}/v3/catalog0/page3.json",
      "@type": "CatalogPage",
      "commitId": "3a94eead-7619-46b6-a502-13d7a21d9a97",
      "commitTimeStamp": "2015-02-01T06:58:47.9532886Z",
      "count": 1,
      "items": [
        {
          "@id": "#{address}/v3/catalog0/data/2015.02.01.06.50.55/vlc.1.1.8.json",
          "@type": "nuget:PackageDetails",
          "commitId": "01f2108f-c775-49e6-a9df-c4ab291dbf4d",
          "commitTimeStamp": "2015-02-01T06:50:55.0640465Z",
          "nuget:id": "vlc",
          "nuget:version": "1.1.8"
        }
      ]
    }
  end

  # package data in our server replication of nuget server

  def package1
    {
      "@id": "#{address}/v3/catalog0/data/2015.02.01.06.22.45/adam.jsgenerator.1.1.0.json",
      "authors": "Dave Van den Eynde,Wouter Demuynck",
      "catalog:commitId": "b3f4fc8a-7522-42a3-8fee-a91d5488c0b1",
      "catalog:commitTimeStamp": "2015-02-01T06:22:45.8488496Z",
      "created": "2011-01-07T07:49:35.947Z",
      "description": "Adam.JSGenerator helps producing snippets of JavaScript code from managed code.",
      "id": "Adam.JSGenerator",
      "lastEdited": "0001-01-01T00:00:00Z",
      "published": "2011-03-07T12:34:36.83Z",
      "summary": "Adam.JSGenerator helps producing snippets of JavaScript code from managed code.",
      "version": "1.1.0"
    }
  end

  def package2
    {
      "@id": "#{address}/v3/catalog0/data/2015.02.01.06.22.45/agatha-rrsl.1.2.0.json",
      "authors": "David Bryon",
      "catalog:commitId": "b3f4fc8a-7522-42a3-8fee-a91d5488c0b1",
      "catalog:commitTimeStamp": "2015-02-01T06:22:45.8488496Z",
      "created": "2011-01-07T07:49:37.73Z",
      "description": "Request/Response Service Layer for .NET",
      "id": "Agatha-rrsl",
      "lastEdited": "0001-01-01T00:00:00Z",
      "published": "2011-01-07T07:49:38.247Z",
      "summary": "Request/Response Service Layer for .NET",
      "version": "1.2.0",
    }
  end

  def package3
    {
      "@id": "#{address}/v3/catalog0/data/2015.02.01.06.34.14/structuremap.2.6.2.json",
      "authors": "Jeremy Miller",
      "catalog:commitId": "e5421e4c-fb0a-4fc0-8246-65dd5d4fdd09",
      "catalog:commitTimeStamp": "2015-02-01T06:34:14.750674Z",
      "created": "2011-02-19T05:12:31.237Z",
      "description": "StructureMap is a Dependency Injection / Inversion of Control tool for .Net that can be used to improve the architectural qualities of an object oriented system by reducing the mechanical costs of good design techniques. StructureMap can enable looser coupling between classes and their dependencies, improve the testability of a class structure, and provide generic flexibility mechanisms. Used judiciously, StructureMap can greatly enhance the opportunities for code reuse by minimizing direct coupling between classes and configuration mechanisms.",
      "id": "structuremap",
      "lastEdited": "0001-01-01T00:00:00Z",
      "projectUrl": "http://structuremap.net/structuremap/",
      "published": "2011-02-19T05:12:46.86Z",
      "summary": "StructureMap is a Dependency Injection / Inversion of Control tool for .Net",
      "version": "2.6.2",
    }
  end

  def package4
    {
      "@id": "#{address}/v3/catalog0/data/2015.02.01.06.33.04/elevate.0.1.0.json",
      "authors": "Chris Marinos",
      "catalog:commitId": "fef2290b-3a1f-4f6c-ad7c-f9f36702c9e9",
      "catalog:commitTimeStamp": "2015-02-01T06:33:04.5000408Z",
      "created": "2011-02-14T16:54:10.457Z",
      "description": "An easy to pick up library containing things you wish were in the BCL.",
      "id": "elevate",
      "lastEdited": "0001-01-01T00:00:00Z",
      "projectUrl": "http://elevate.codeplex.com/",
      "published": "2011-02-14T16:54:28.05Z",
      "version": "0.1.0"
    }
  end

  def package5
    {
      "@id": "#{address}/v3/catalog0/data/2015.02.01.06.50.55/vlc.1.1.8.json",
      "authors": "VideoLAN Organization",
      "catalog:commitId": "01f2108f-c775-49e6-a9df-c4ab291dbf4d",
      "catalog:commitTimeStamp": "2015-02-01T06:50:55.0640465Z",
      "created": "2011-03-30T20:39:48.437Z",
      "description": "VLC is a free and open source cross-platform multimedia player and\nframework that plays most multimedia files as well as DVD, Audio CD,\nVCD, and various streaming protocols. Please install with chocolatey (http://nuget.org/List/Packages/chocolatey).",
      "id": "vlc",
      "lastEdited": "0001-01-01T00:00:00Z",
      "projectUrl": "http://www.videolan.org/vlc/",
      "published": "1900-01-01T00:00:00Z",
      "summary": "VLC Media Player",
      "title": "VLC",
      "version": "1.1.8"
    }
  end

  def address
    "http://" + "#{@serv.addr[2]}:#{@serv.addr[1]}"
  end

  def close
    @closing = true
    @serv.close
  end

  def start
    @serv = TCPServer.new("127.0.0.1", 0)
    @closing = false
    server_thread = Thread.new do
      begin
        while conn = @serv.accept
          m, path, _ = conn.gets.split(" ")
          headers = parse_headers(conn)
          data = conn.read(headers["Content-Length"].to_i)
          ret = handle_request(m, path, Addressable::URI.unescape(data))

          conn.print "HTTP/1.1 200\r\n"
          if "GET" == m
            conn.print "Content-Type: text/html\r\n"
            conn.print "\r\n"
            conn.print ret.to_s
          end
          conn.close
        end
      rescue IOError
        raise unless @closing
      end

    end
    server_thread.abort_on_exception
  end

  private

  def handle_request(method, path, data)
    case path
    when "/v3/catalog0/index.json"
      return index.to_json
    when "/v3/catalog0/page0.json"
      return page0.to_json
    when "/v3/catalog0/page1.json"
      return page1.to_json
    when "/v3/catalog0/page2.json"
      return page2.to_json
    when "/v3/catalog0/data/2015.02.01.06.22.45/adam.jsgenerator.1.1.0.json"
      return package1.to_json
    when "/v3/catalog0/data/2015.02.01.06.22.45/agatha-rrsl.1.2.0.json"
      return package2.to_json
    when "/v3/catalog0/data/2015.02.01.06.34.14/structuremap.2.6.2.json"
      return package3.to_json
    when "/v3/catalog0/data/2015.02.01.06.33.04/elevate.0.1.0.json"
      return package4.to_json
    when "/v3/catalog0/data/2015.02.01.06.50.55/vlc.1.1.8.json"
      return package5.to_json
    else
      nil
    end
  end

  def parse_headers(request)
    headers = {}
    while line = request.gets.split(" ", 2)
      break if line[0] == ""
      headers[line[0].chop] = line[1].strip
    end
    headers
  end
end
