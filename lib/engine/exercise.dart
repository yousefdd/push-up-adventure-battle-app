import 'angles.dart';
import 'pose.dart';

/// Pushups only, in the two modes the source app offers: full and knee.
enum ExerciseType { pushup, kneePushup }

/// The tunable thresholds for one pushup mode. Defaults are reconstructed from
/// the source app's behaviour (a rep only counts once the elbow bends past
/// 100 degrees), then rounded to clean, explainable numbers.
class ExerciseProfile {
  const ExerciseProfile({
    required this.type,
    required this.label,
    required this.blurb,
    required this.downAngle,
    required this.upAngle,
    required this.minRepSeconds,
    required this.minBottomSeconds,
    required this.maxBottomSeconds,
  });

  final ExerciseType type;

  /// Title and one-line description, worded as in the source app.
  final String label;
  final String blurb;

  /// Elbow angle (deg) that must be reached at the bottom for real depth.
  final double downAngle;

  /// Elbow angle (deg) that counts as fully extended again, closing the rep.
  final double upAngle;

  /// Shortest believable full rep. Anything faster is a bounce, not a rep.
  final double minRepSeconds;

  /// Shortest pause at the bottom; stops people flying through half reps.
  final double minBottomSeconds;

  /// Longest pause at the bottom before it reads as a rest instead of a rep.
  final double maxBottomSeconds;

  /// Elbow angle (shoulder -> elbow -> wrist), averaged over both arms, or
  /// null when neither arm is reliably visible this frame.
  double? measure(PoseFrame f) {
    final left = Angles.jointAngle(
      f.reliable(LandmarkType.leftShoulder),
      f.reliable(LandmarkType.leftElbow),
      f.reliable(LandmarkType.leftWrist),
      aspect: f.aspect,
    );
    final right = Angles.jointAngle(
      f.reliable(LandmarkType.rightShoulder),
      f.reliable(LandmarkType.rightElbow),
      f.reliable(LandmarkType.rightWrist),
      aspect: f.aspect,
    );
    return Angles.bilateral(left, right);
  }

  static const Map<ExerciseType, ExerciseProfile> defaults = {
    ExerciseType.pushup: ExerciseProfile(
      type: ExerciseType.pushup,
      label: 'Full pushups',
      blurb: 'Toes on the floor, body straight',
      // A phone on the floor sees the arms from the front, where a full-depth
      // push-up reads about 105–115°; 120° counts it, a half rep (~135°) does not.
      downAngle: 120,
      upAngle: 150,
      minRepSeconds: 0.5,
      minBottomSeconds: 0.08,
      maxBottomSeconds: 4.0,
    ),
    ExerciseType.kneePushup: ExerciseProfile(
      type: ExerciseType.kneePushup,
      label: 'Knee pushups',
      blurb: 'Knees on the floor — easier, still counts',
      downAngle: 125,
      upAngle: 150,
      minRepSeconds: 0.45,
      minBottomSeconds: 0.08,
      maxBottomSeconds: 4.0,
    ),
  };
}
