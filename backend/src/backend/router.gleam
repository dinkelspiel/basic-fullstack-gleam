import backend/web
import cors_builder as cors
import gleam/dynamic
import gleam/http.{Get, Post as WispPost}
import gleam/json
import gleam/list
import gleam/result
import simplifile
import wisp.{type Request, type Response}

pub fn handle_request(req: Request) -> Response {
  use req <- web.middleware(req)
  use req <- cors.wisp_middleware(
    req,
    cors.new()
      |> cors.allow_origin("http://localhost:1234")
      |> cors.allow_method(http.Get)
      |> cors.allow_method(http.Post)
      |> cors.allow_header("Content-Type"),
  )

  case wisp.path_segments(req) {
    ["posts"] ->
      case req.method {
        // If the user requests the posts route
        Get -> list_posts(req)
        // And the method is GET, return a list of all posts, we will create this function later
        WispPost -> create_post(req)
        // And if the method is POST create a post, we will create this function later
        _ -> wisp.method_not_allowed([Get, WispPost])
        // And if its neither return an invalid method error
      }
    _ -> wisp.not_found()
    // If the route is not /posts return a 404 not found
  }
}

type Post {
  // Create a type that models our post
  Post(id: Int, title: String, body: String)
}

fn list_posts(req: Request) -> Response {
  // Here we will use blocks and use statements and i will explain them more in detail later

  let result = {
    use file_data <- result.try(
      simplifile.read(from: "./data.json")
      |> result.replace_error("Problem reading data.json"),
    )
    // To avoid this post getting even *longer* i will use a file as a database. Gleam and databases is for another article. Simplifile is a standard for filesystem usage in Gleam so we use it here

    // Here we will parse our data from json to a type and then back into json to simulate this coming from a database of some sort but this could really just be a simple returning of the file_data if you wanted to if you are just doing files that map directly to the response.

    let posts_decoder =
      // Create a decoder that parses a list of posts eg. [{id: 1, title: "Post", body: "Body"}]
      dynamic.list(dynamic.decode3(
        Post,
        dynamic.field("id", dynamic.int),
        dynamic.field("title", dynamic.string),
        dynamic.field("body", dynamic.string),
      ))

    use posts <- result.try(
      json.decode(from: file_data, using: posts_decoder)
      |> result.replace_error("Problem decoding file_data to posts"),
    )
    // Take our string file_data and turn it into our Post type using our decoder

    Ok(
      json.array(posts, fn(post) {
        // Encode our
        json.object([
          #("id", json.int(post.id)),
          #("title", json.string(post.title)),
          #("body", json.string(post.body)),
        ])
      }),
    )
  }

  case result {
    Ok(json) -> wisp.json_response(json |> json.to_string_builder, 200)
    // Return our json posts that we turn into a string_builder as thats whats required with a code of 200 meaning OK.
    Error(_) -> wisp.unprocessable_entity()
    // If we encounter an error we send an empty response. If this were a real application it'd probably be best to send a json_response back.
  }
}

// Create a type for our create post request data
type CreatePost {
  CreatePost(title: String, body: String)
}

fn create_post(req: Request) -> Response {
  // We will use the same scaffolding as we use in the list_posts example with our result so that can go unchanged

  // Get the json body from our request
  use body <- wisp.require_json(req)

  let result = {
    // Create a decoder for our request data
    let create_post_decoder =
      dynamic.decode2(
        CreatePost,
        dynamic.field("title", dynamic.string),
        dynamic.field("body", dynamic.string),
      )

    use parsed_request <- result.try(case create_post_decoder(body) {
      // Decode our body to the CreatePost type
      Ok(parsed) -> Ok(parsed)
      Error(_) -> Error("Invalid body recieved")
    })

    use file_data <- result.try(
      simplifile.read(from: "./data.json")
      |> result.replace_error("Problem reading data.json"),
    )
    // Load the posts again from the file

    let posts_decoder =
      // Create a decoder that parses a list of posts eg. [{id: 1, title: "Post", body: "Body"}]
      dynamic.list(dynamic.decode3(
        Post,
        dynamic.field("id", dynamic.int),
        dynamic.field("title", dynamic.string),
        dynamic.field("body", dynamic.string),
      ))

    use posts <- result.try(
      json.decode(from: file_data, using: posts_decoder)
      |> result.replace_error("Problem decoding file_data to posts"),
    )
    // Take our string file_data and turn it into our Post type using our decoder

    // Add the new post to the old posts
    let new_posts =
      list.append(posts, [
        Post(
          id: list.length(posts),
          title: parsed_request.title,
          body: parsed_request.body,
        ),
      ])

    let new_posts_as_json =
      json.array(new_posts, fn(post) {
        // Encode our posts to json
        json.object([
          #("id", json.int(post.id)),
          #("title", json.string(post.title)),
          #("body", json.string(post.body)),
        ])
      })

    let _ =
      new_posts_as_json
      |> json.to_string
      // Turn the new posts json into a string
      |> simplifile.write(to: "./data.json")
    // And write it to our data.json file

    Ok("Successfully created post")
    // Return a success message
  }

  case result {
    Ok(message) ->
      wisp.json_response(
        json.object([#("message", json.string(message))])
          |> json.to_string_builder,
        200,
      )
    // Return our success
    Error(_) -> wisp.unprocessable_entity()
    // If we encounter an error we send an empty response. If this were a real application it'd probably be best to send a json_response back.
  }
}
