import gleam/dynamic
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/uri.{type Uri}
import lustre
import lustre/attribute.{href, type_}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html.{a, button, div, form, input, text}
import lustre/event
import lustre_http
import modem

pub fn main() {
  lustre.application(init, update, view)
  |> lustre.start("#app", Nil)
}

// Define our route type
pub type Route {
  Home
  About
  ShowPost(post_id: Int)
  NotFound
}

// Include that route in our model
type Model {
  Model(
    route: Route,
    posts: List(Post),
    title: String,
    // Add title and body to our model. These will be the values we create our post with
    body: String,
  )
}

pub type Post {
  Post(id: Int, title: String, body: String)
}

fn get_posts() {
  let decoder =
    dynamic.list(
      // We want to decode a list so we use a dynamic.list here
      dynamic.decode3(
        // And it is a list of json that looks like this {id: 1, title: "title", body: "body"} so we use a decodeN matching the number of arguments
        Post,
        // You input the type of your data here
        dynamic.field("id", dynamic.int),
        // Then here and for the following lines you define the field with the name and the type
        dynamic.field("title", dynamic.string),
        dynamic.field("body", dynamic.string),
      ),
    )

  lustre_http.get(
    // Then you call lustre_http get
    "http://localhost:8000/posts",
    // This will be a call to our future backend
    lustre_http.expect_json(decoder, GotPosts),
    // Then lustre_http exposes a method to parse the resulting data as json that takes in our json decoder from earlier
  )
}

// Define our OnRouteChange message in our messages
pub type Msg {
  OnRouteChange(Route)
  GotPosts(Result(List(Post), lustre_http.HttpError))
  TitleUpdated(value: String)
  // Add Title and Body updated to handle the input updating in the frontend to sync it with the state of our lustre application
  BodyUpdated(value: String)
  RequestCreatePost
  // Create a message for our form to create the post
  CreatePostResponded(Result(MessageErrorResponse, lustre_http.HttpError))
  // Create a message for when the backend send back a result
  // In gleam we can include data in our types so here we add Route data to our OnRouteChange message
}

// Gleam doesn't expose any functions for getting the current url so we will use the ffi functionality to import this function from javascript later. In laymans terms this makes Gleam be able to import any javascript and use it as a function.
@external(javascript, "./ffi.mjs", "get_route")
fn do_get_route() -> String

// Define our function where we get our route
fn get_route() -> Route {
  let uri = case do_get_route() |> uri.parse {
    Ok(uri) -> uri
    _ -> panic as "Invalid uri"
    // The uri is coming from our javascript integration so an invalid uri should be unreachable state so we can safely panic here
  }

  case uri.path |> uri.path_segments {
    // Here we match for the route in the uri split on the slashes so / becomes [] and /about becomes ["about"] and so on
    [] -> Home
    ["about"] -> About
    ["post", post_id_string] -> {
      let assert Ok(post_id) = int.parse(post_id_string)
      // Here we parse our post_id from our url and require it to be an int. Ideally in a production application you'd do some error handling here but we only care if it's an integer.
      ShowPost(post_id)
      // Return the route Post with our post_id
    }
    _ -> NotFound
  }
}

// Define our function for handling when the route changes
fn on_url_change(uri: Uri) -> Msg {
  OnRouteChange(get_route())
  // When the url changes dispatch the message for when the route changes with the new route that we get from our get_route() function
}

// Create our model initialization
fn init(_) -> #(Model, Effect(Msg)) {
  #(
    Model(
      route: get_route(),
      posts: [],
      title: "",
      body: "",
      // Here we can get the current route when the page is initialized in the browser
    ),
    effect.batch([
      modem.init(on_url_change),
      // Move the modem.init here inside the new effect.batch
      get_posts(),
    ]),
  )
}

pub type MessageErrorResponse {
  MessageErrorResponse(message: Option(String), error: Option(String))
}

fn create_post(model: Model) {
  lustre_http.post(
    "http://localhost:8000/posts",
    // This will be a call to our future backends create post route
    json.object([
      #("title", json.string(model.title)),
      #("body", json.string(model.body)),
    ]),
    lustre_http.expect_json(
      dynamic.decode2(
        MessageErrorResponse,
        dynamic.optional_field("message", dynamic.string),
        dynamic.optional_field("error", dynamic.string),
      ),
      CreatePostResponded,
    ),
  )
}

// Create our update method
fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    OnRouteChange(route) -> #(
      Model(
        ..model,
        // This isn't neccesary currently but is required to keep the state between the route changes
        route: route,
      ),
      effect.none(),
      // This just tells our program to not do anything after
    )
    GotPosts(posts_result) ->
      case posts_result {
        Ok(posts) -> #(Model(..model, posts: posts), effect.none())
        // Here we set the state to our current state + our new posts
        Error(_) -> panic
      }
    TitleUpdated(value) -> #(
      // If the user updates the title input
      Model(..model, title: value),
      // Then we update the current model with the current state and we modify the title to the new value
      effect.none(),
    )
    BodyUpdated(value) -> #(
      // Same with the body
      Model(..model, body: value),
      effect.none(),
    )
    RequestCreatePost -> #(model, create_post(model))
    // Run the create_post function if the RequestCreatePost message was recieved from the frontend.
    CreatePostResponded(response) -> #(model, get_posts())
    // If the create post responded then we want to refetch our posts
  }
}

// Now we can define our view with our html
fn view(model: Model) -> Element(Msg) {
  case model.route {
    Home ->
      div(
        [],
        list.append(
          [
            form([event.on_submit(RequestCreatePost)], [
              // If the user submits the form by clicking on the button we request gleam to create our post
              text("Title"),
              input([event.on_input(TitleUpdated)]),
              // event.on_input sends the message TitleUpdated each time the user updates the input
              text("Body"),
              input([event.on_input(BodyUpdated)]),
              // Same here but for BodyUpdated
              button([type_("submit")], [text("Create Post")]),
            ]),
          ],
          list.map(model.posts, fn(post) {
            // Loop over all posts in our model
            a([href("/post/" <> int.to_string(post.id))], [
              // Return a link to /post/(post_id)
              text(post.title),
              // With the post title as the link value
            ])
          }),
        ),
      )
    ShowPost(post_id) -> {
      // If we are on the post page with a valid post_id
      let assert Ok(post) =
        list.find(model.posts, fn(post) { post.id == post_id })
      // We find the post matching our post_id. Same as the post_id parsing but we only care if the value is valid so we don't care about error handling.

      div([], [
        // Show our target post
        text(post.title),
        text("/"),
        text(post.body),
      ])
    }
    About -> div([], [text("You are on the about page")])
    NotFound -> div([], [text("404 Not Found")])
  }
}
