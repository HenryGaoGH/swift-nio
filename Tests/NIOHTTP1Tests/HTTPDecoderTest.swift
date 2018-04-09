//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import Dispatch
import NIO
import NIOHTTP1

class HTTPDecoderTest: XCTestCase {
    private var channel: EmbeddedChannel!
    private var loop: EmbeddedEventLoop!

    override func setUp() {
        self.channel = EmbeddedChannel()
        self.loop = channel.eventLoop as! EmbeddedEventLoop
    }

    override func tearDown() {
        self.channel = nil
        self.loop = nil
    }

    func testDoesNotDecodeRealHTTP09Request() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestDecoder()).wait())

        // This is an invalid HTTP/0.9 simple request (too many CRLFs), but we need to
        // trigger https://github.com/nodejs/http-parser/issues/386 or http_parser won't
        // actually parse this at all.
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "GET /a-file\r\n\r\n")

        do {
            try channel.writeInbound(buffer)
            XCTFail("Did not error")
        } catch HTTPParserError.invalidVersion {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

       loop.run()
    }

    func testDoesNotDecodeFakeHTTP09Request() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestDecoder()).wait())

        // This is a HTTP/1.1-formatted request that claims to be HTTP/0.9.
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "GET / HTTP/0.9\r\nHost: whatever\r\n\r\n")

        do {
            try channel.writeInbound(buffer)
            XCTFail("Did not error")
        } catch HTTPParserError.invalidVersion {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        loop.run()
    }

    func testDoesNotDecodeHTTP2XRequest() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestDecoder()).wait())

        // This is a hypothetical HTTP/2.0 protocol request, assuming it is
        // byte for byte identical (which such a protocol would never be).
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "GET / HTTP/2.0\r\nHost: whatever\r\n\r\n")

        do {
            try channel.writeInbound(buffer)
            XCTFail("Did not error")
        } catch HTTPParserError.invalidVersion {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        loop.run()
    }

    func testToleratesHTTP13Request() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestDecoder()).wait())

        // We tolerate higher versions of HTTP/1 than we know about because RFC 7230
        // says that these should be treated like HTTP/1.1 by our users.
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "GET / HTTP/1.3\r\nHost: whatever\r\n\r\n")

        XCTAssertNoThrow(try channel.writeInbound(buffer))
        XCTAssertNoThrow(try channel.finish())
    }

    func testDoesNotDecodeRealHTTP09Response() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestEncoder()).wait())
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPResponseDecoder()).wait())

        // We need to prime the decoder by seeing a GET request.
        try channel.writeOutbound(HTTPClientRequestPart.head(HTTPRequestHead(version: .init(major: 0, minor: 9), method: .GET, uri: "/")))

        // The HTTP parser has no special logic for HTTP/0.9 simple responses, but we'll send
        // one anyway just to prove it explodes.
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "This is file data\n")

        do {
            try channel.writeInbound(buffer)
            XCTFail("Did not error")
        } catch HTTPParserError.invalidConstant {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        loop.run()
    }

    func testDoesNotDecodeFakeHTTP09Response() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestEncoder()).wait())
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPResponseDecoder()).wait())

        // We need to prime the decoder by seeing a GET request.
        try channel.writeOutbound(HTTPClientRequestPart.head(HTTPRequestHead(version: .init(major: 0, minor: 9), method: .GET, uri: "/")))

        // The HTTP parser rejects HTTP/1.1-formatted responses claiming 0.9 as a version.
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "HTTP/0.9 200 OK\r\nServer: whatever\r\n\r\n")

        do {
            try channel.writeInbound(buffer)
            XCTFail("Did not error")
        } catch HTTPParserError.invalidVersion {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        loop.run()
    }

    func testDoesNotDecodeHTTP2XResponse() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestEncoder()).wait())
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPResponseDecoder()).wait())

        // We need to prime the decoder by seeing a GET request.
        try channel.writeOutbound(HTTPClientRequestPart.head(HTTPRequestHead(version: .init(major: 2, minor: 0), method: .GET, uri: "/")))

        // This is a hypothetical HTTP/2.0 protocol response, assuming it is
        // byte for byte identical (which such a protocol would never be).
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "HTTP/2.0 200 OK\r\nServer: whatever\r\n\r\n")

        do {
            try channel.writeInbound(buffer)
            XCTFail("Did not error")
        } catch HTTPParserError.invalidVersion {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        loop.run()
    }

    func testToleratesHTTP13Response() throws {
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPRequestEncoder()).wait())
        XCTAssertNoThrow(try channel.pipeline.add(handler: HTTPResponseDecoder()).wait())

        // We need to prime the decoder by seeing a GET request.
        try channel.writeOutbound(HTTPClientRequestPart.head(HTTPRequestHead(version: .init(major: 2, minor: 0), method: .GET, uri: "/")))

        // We tolerate higher versions of HTTP/1 than we know about because RFC 7230
        // says that these should be treated like HTTP/1.1 by our users.
        var buffer = channel.allocator.buffer(capacity: 64)
        buffer.write(staticString: "HTTP/1.3 200 OK\r\nServer: whatever\r\n\r\n")

        XCTAssertNoThrow(try channel.writeInbound(buffer))
        XCTAssertNoThrow(try channel.finish())
    }
}