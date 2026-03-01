import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/review_repository.dart';
import '../timer/timer_provider.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(appDatabaseProvider));
});

// Signal to refresh review list after mutations
final reviewRefreshSignal = StateProvider<int>((ref) => 0);

final activeReviewItemsProvider = FutureProvider<List<ReviewItem>>((ref) {
  ref.watch(reviewRefreshSignal);
  return ref.watch(reviewRepositoryProvider).getActiveItems();
});

final dueReviewItemsProvider = FutureProvider<List<ReviewItem>>((ref) {
  ref.watch(reviewRefreshSignal);
  return ref.watch(reviewRepositoryProvider).getDueItems();
});
