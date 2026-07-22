import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/task.dart';

/// Cloud sync layer — mirrors tasks to Firestore in real time so the
/// same account sees the same tasks on Android and desktop.
class SyncService {
  static bool enabled = true;

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get uid => auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _tasksCollection {
    final u = uid;
    if (u == null) return null;
    return _db.collection('users').doc(u).collection('tasks');
  }

  Future<UserCredential> signInAnonymously() {
    return auth.signInAnonymously();
  }

  Future<UserCredential> signInWithEmail(String email, String password) {
    return auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmail(String email, String password) {
    return auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => auth.signOut();

  Future<void> pushTask(Task task) async {
    final col = _tasksCollection;
    if (col == null) return;
    await col.doc(task.id).set(task.toMap());
  }

  Future<void> deleteTaskRemote(String id) async {
    final col = _tasksCollection;
    if (col == null) return;
    await col.doc(id).delete();
  }

  Stream<List<Task>> taskStream() {
    final col = _tasksCollection;
    if (col == null) return const Stream.empty();
    return col.snapshots().map(
          (snap) => snap.docs.map((d) => Task.fromMap(d.data())).toList(),
        );
  }
}
