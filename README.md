### Introduction
MantleData provides several tools to help implement the Model-ViewModel-View architecture in a Cocoa or Cocoa Touch application. Specifically, it includes a Core Data wrapper, and several constructs built around the ReactiveSet protocol - an abstract sectioned collection.

### Example
```
class TweetListViewModel {
  let tweets: ViewModelSet<TweetViewModel>

  init(container: Container) {
    tweets = container.prepare { context in
      return Tweet.with(context).all()      // return type: ObjectSet<Tweet>
    }
  }
}
```

#### Mapping between Application Layers
MantleData provides `ObjectSet` at the Model layer, an `NSFetchedResultsController` equivalent, to manage a dynamic set of objects bound to an predicate. It conforms to the `ReactiveSet` protocol, which is an abstract sectioned collection.

On the other hand, `ViewModelSet` is provided at the ViewModel layer for exposing a collection of view models to the View layer, taking any qualifying `ReactiveSet` as a source. The view model must conform to the `ViewModel` protocol, which requires implementations to constrain the model layer object it can take (`ViewModel.MappingObject`).
