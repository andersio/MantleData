### Introduction
MantleData provides several tools to help implement the Model-ViewModel-View architecture in a Cocoa or Cocoa Touch application. Specifically, it includes a Core Data wrapper, and several constructs built around the ReactiveSet protocol - an abstract sectioned collection.

### Example
```
class TweetListViewModel {
  let tweets: ViewModelSet<TweetViewModel>

  init(container: Container) {
    let tweetsSet: ObjectSet<Tweet> = container
      .prepareOnMainThread { context in
        Tweet.with(context) { builder in
          builder.sort(byKeyPath: "date", order: .descending)
        }.resultObjectSet
      }
    
    tweets = ViewModelSet(tweetsSet) { tweet in
      TweetViewModel(for: tweet)
    }
  }
}
```
