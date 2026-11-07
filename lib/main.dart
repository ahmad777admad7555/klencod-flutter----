import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  runApp(const CatchUpApp());
}

class CatchUpApp extends StatelessWidget {
  const CatchUpApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Catch Up',
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final _game = GameLogic(Level(20240117));
  bool _left = false, _right = false, _jump = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _game.left = _left;
      _game.right = _right;
      _game.jumpHeld = _jump;
      _game.update();
      setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) {
          if (!_game.started) _game.started = true;
          _handleTouch(d.localPosition, true);
        },
        onPanUpdate: (d) => _handleTouch(d.localPosition, true),
        onPanEnd: (_) {
          _left = _right = _jump = false;
        },
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(painter: GamePainter(_game)),
          ),
          // أزرار بصرية شفافة
          Positioned(
            left: 0, bottom: 0, top: 0, width: 70,
            child: Container(color: Colors.transparent),
          ),
        ]),
      ),
    );
  }

  void _handleTouch(Offset pos, bool down) {
    final w = MediaQuery.of(context).size.width;
    if (pos.dx < w * 0.16) {
      _left = true; _right = false; _jump = false;
    } else if (pos.dx < w * 0.35) {
      _left = false; _right = true; _jump = false;
    } else if (pos.dx > w * 0.55) {
      _left = false; _right = false; _jump = true;
    } else {
      _left = _right = _jump = false;
    }
  }
}

// ================= Level =================
class Plat {
  final int x, y, w, biome;
  const Plat(this.x, this.y, this.w, this.biome);
}

class Level {
  static const int vw = 320, vh = 180, pt = 8;
  final List<Plat> plats = [];
  final List<int> biomeY = [0, 0];
  double topY = 0;

  Level(int seed) {
    final rng = Random(seed);
    plats.add(const Plat(110, 0, 130, 0));
    double cx = 175, cy = 0;

    for (int i = 1; i <= 45; i++) {
      final biome = i < 15 ? 0 : (i < 30 ? 1 : 2);
      final w = 36 + rng.nextInt(56);
      double dy, dx;
      do {
        dy = 50 + rng.nextInt(65).toDouble();
        dx = -80 + rng.nextInt(161).toDouble();
      } while (dy > 85 && dx.abs() > 55);

      double ncx = cx + dx;
      ncx = ncx.clamp(w / 2.0 + 16, vw - w / 2.0 - 16);
      cy -= dy;
      plats.add(Plat((ncx - w / 2.0).toInt(), cy.toInt(), w, biome));
      cx = ncx;
    }
    biomeY[0] = plats[15].y;
    biomeY[1] = plats[30].y;
    topY = plats.last.y.toDouble();
  }

  int biomeOf(double y) {
    if (y > biomeY[0]) return 0;
    if (y > biomeY[1]) return 1;
    return 2;
  }
}

// ================= GameLogic =================
class GameLogic {
  static const double g = 0.55;
  static const double jumpMin = 3.2;
  static const double jumpMax = 13.6;
  static const double move = 2.2;
  static const double airAccel = 0.08;
  static const double maxFall = 12.0;
  static const double chargeRate = 0.018;
  static const int pw = 8, ph = 10, fallLimit = 340;

  final Level level;

  double px = 0, py = 0, vx = 0, vy = 0;
  bool onGround = false, charging = false, facingRight = true;
  double charge = 0;
  double checkpointPX = 0, checkpointPY = 0;
  int deaths = 0, coyote = 0;
  double cameraY = 0, shake = 0;
  bool started = false, paused = false;
  bool left = false, right = false, jumpHeld = false;
  bool _jumpPrev = false;

  GameLogic(this.level) {
    checkpointPX = 175 - pw / 2.0;
    px = checkpointPX;
    py = checkpointPY - ph;
    cameraY = -(Level.vh * 0.55);
    cameraY = min(cameraY, -Level.vh + 40);
    cameraY = max(cameraY, level.topY - 60);
  }

  void update() {
    if (paused) return;

    if (onGround) {
      vx = (right ? move : 0) - (left ? move : 0);
      if (vx > 0) facingRight = true;
      if (vx < 0) facingRight = false;
    } else {
      if (left) vx -= airAccel;
      if (right) vx += airAccel;
      vx = vx.clamp(-move, move);
    }

    if (jumpHeld) {
      if (!_jumpPrev) {
        if (onGround || coyote > 0) {
          charging = true;
          charge = 0;
          started = true;
        }
      } else if (charging) {
        charge = min(1.0, charge + chargeRate);
      }
    } else {
      if (_jumpPrev && charging) {
        vy = -(jumpMin + (jumpMax - jumpMin) * charge);
        charging = false;
        onGround = false;
        coyote = 0;
        shake = max(shake, charge * 1.5);
        charge = 0;
      }
    }
    _jumpPrev = jumpHeld;

    vy += g;
    if (vy > maxFall) vy = maxFall;

    px += vx;
    _collideX();
    py += vy;
    _collideY();

    if (px < 0) {
      px = 0;
      vx = 0;
    }
    if (px > Level.vw - pw) {
      px = Level.vw - pw.toDouble();
      vx = 0;
    }

    if (!onGround && charging && vy > 0.5) {
      charging = false;
      charge = 0;
    }

    if (onGround) {
      coyote = 6;
    } else if (coyote > 0) {
      coyote--;
    }

    if (py > checkpointPY + fallLimit) {
      deaths++;
      shake = 4;
      _resetCheckpoint();
      return;
    }

    final target = py - Level.vh * 0.55;
    cameraY += (target - cameraY) * 0.12;
    cameraY = min(cameraY, -Level.vh + 40);
    cameraY = max(cameraY, level.topY - 60);
    if (shake > 0.05) {
      shake *= 0.85;
    } else {
      shake = 0;
    }
  }

  void _resetCheckpoint() {
    px = checkpointPX;
    py = checkpointPY - ph;
    vx = 0;
    vy = 0;
    charge = 0;
    charging = false;
    onGround = false;
    coyote = 0;
  }

  void _collideX() {
    for (final p in level.plats) {
      if (px + pw > p.x && px < p.x + p.w && py + ph > p.y && py < p.y + Level.pt) {
        if (vx > 0) {
          px = p.x - pw.toDouble();
        } else if (vx < 0) {
          px = p.x + p.w.toDouble();
        }
        vx = 0;
      }
    }
  }

  void _collideY() {
    onGround = false;
    for (final p in level.plats) {
      if (px + pw > p.x && px < p.x + p.w && py + ph > p.y && py < p.y + Level.pt) {
        if (vy >= 0) {
          py = p.y - ph.toDouble();
          vy = 0;
          onGround = true;
          if (p.y < checkpointPY) {
            checkpointPY = p.y.toDouble();
            checkpointPX = p.x + p.w / 2.0 - pw / 2.0;
          }
        } else {
          py = p.y + Level.pt.toDouble();
          vy = 0;
        }
      }
    }
  }
}

// ================= GamePainter =================
class GamePainter extends CustomPainter {
  final GameLogic game;
  GamePainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / Level.vw;
    final scaleY = size.height / Level.vh;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final biome = game.level.biomeOf(game.py);
    _drawSky(canvas, biome);
    _drawPlatforms(canvas, biome);
    _drawCat(canvas);
    _drawHud(canvas, biome);

    if (!game.started) {
      _overlay(canvas, 'CATCH UP',
          'Hold right side to charge — release to jump');
    }
    if (game.paused) {
      _overlay(canvas, 'PAUSED', 'Tap to resume');
    }

    canvas.restore();
  }

  void _drawSky(Canvas c, int biome) {
    final colors = [
      [const Color(0xFF87B8D4), const Color(0xFFB8D8E8)],
      [const Color(0xFF1A1428), const Color(0xFF3A2D55)],
      [const Color(0xFF3B1F12), const Color(0xFFA85F2E)],
    ][biome];
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(
          Rect.fromLTWH(0, 0, Level.vw.toDouble(), Level.vh.toDouble()));
    c.drawRect(
        Rect.fromLTWH(0, 0, Level.vw.toDouble(), Level.vh.toDouble()), paint);

    if (biome == 0) {
      final sunPaint = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0x88FFF4C0),
          const Color(0x00FFF4C0),
        ]).createShader(const Rect.fromLTWH(180, -40, 180, 180));
      c.drawCircle(const Offset(260, 40), 90, sunPaint);
    } else if (biome == 1) {
      final moonPaint = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0x669A7BC8),
          const Color(0x009A7BC8),
        ]).createShader(const Rect.fromLTWH(-10, -40, 140, 140));
      c.drawCircle(const Offset(60, 30), 70, moonPaint);
      final moonBody = Paint()..color = const Color(0xFFE8E0F0);
      c.drawCircle(const Offset(240, 45), 18, moonBody);
      final moonShadow = Paint()..color = const Color(0xFF1A1428);
      c.drawCircle(const Offset(232, 40), 16, moonShadow);
    } else {
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0x88FFB060),
          const Color(0x00FFB060),
        ]).createShader(const Rect.fromLTWH(80, -60, 240, 240));
      c.drawCircle(const Offset(200, 60), 120, glow);
    }
  }

  void _drawPlatforms(Canvas c, int biome) {
    final topColors = [0xFF9AC96A, 0xFFA898D0, 0xFFD4A070];
    final midColors = [0xFF5E8E3C, 0xFF6B5A88, 0xFF8A5A32];
    final botColors = [0xFF3E6230, 0xFF3D3057, 0xFF6B4423];

    for (final p in game.level.plats) {
      final sy = (p.y - game.cameraY);
      if (sy < -30 || sy > Level.vh + 30) continue;

      final shadow = Paint()..color = const Color(0x40000000);
      c.drawRect(
          Rect.fromLTWH(p.x + 2, sy + 3, p.w.toDouble(), Level.pt.toDouble()),
          shadow);

      final bodyPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(topColors[biome]),
            Color(botColors[biome]),
          ],
        ).createShader(
            Rect.fromLTWH(p.x.toDouble(), sy, p.w.toDouble(), Level.pt.toDouble()));
      c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(p.x.toDouble(), sy, p.w.toDouble(), Level.pt.toDouble()),
            const Radius.circular(2),
          ),
          bodyPaint);

      final topPaint = Paint()..color = Color(midColors[biome]);
      c.drawRect(Rect.fromLTWH(p.x + 1, sy + 1, (p.w - 2).toDouble(), 2),
          topPaint);
    }
  }

  void _drawCat(Canvas c) {
    final cx = game.px;
    final cy = game.py - game.cameraY;

    final shadowPaint = Paint()..color = const Color(0x50000000);
    c.drawOval(
        Rect.fromCenter(
            center: Offset(cx + 4, cy + 12), width: 12, height: 3),
        shadowPaint);

    final bodyPaint = Paint()..color = const Color(0xFFE8A33D);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx, cy + 2, 8, 8),
            const Radius.circular(2),
        ),
        bodyPaint);

    // أذنان
    final earPaint = Paint()..color = const Color(0xFFE8A33D);
    final earL = Path()
      ..moveTo(cx + 1, cy + 2)
      ..lineTo(cx + 3, cy - 1)
      ..lineTo(cx + 4, cy + 2)
      ..close();
    c.drawPath(earL, earPaint);
    final earR = Path()
      ..moveTo(cx + 4, cy + 2)
      ..lineTo(cx + 5, cy - 1)
      ..lineTo(cx + 7, cy + 2)
      ..close();
    c.drawPath(earR, earPaint);

    // عين
    final eyeWhite = Paint()..color = Colors.white;
    final eyeDark = Paint()..color = const Color(0xFF101820);
    final ex = game.facingRight ? cx + 5 : cx + 1;
    c.drawCircle(Offset(ex, cy + 5), 1.2, eyeWhite);
    c.drawCircle(Offset(ex, cy + 5), 0.7, eyeDark);

    // شريط شحن
    if (game.charging) {
      final bgPaint = Paint()..color = const Color(0xAA000000);
      c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 5, cy - 9, 18, 4),
            const Radius.circular(2),
          ),
          bgPaint);
      final fillPaint = Paint()..color = const Color(0xFF3AD6C0);
      c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 4, cy - 8, 16 * game.charge, 2),
            const Radius.circular(1),
          ),
          fillPaint);
    }
  }

  void _drawHud(Canvas c, int biome) {
    final titlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final tp = TextPainter(
      text: const TextSpan(
        text: 'CATCH UP',
        style: TextStyle(
            color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, const Offset(6, 3));

    final info = TextPainter(
      text: TextSpan(
        text: 'Deaths: ${game.deaths}',
        style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 7),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    info.paint(c, const Offset(6, 15));

    final biomeNames = ['Forest', 'The Deep', 'Ruins'];
    final biomeTp = TextPainter(
      text: TextSpan(
        text: biomeNames[biome],
        style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 7),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    biomeTp.paint(c, const Offset(6, 24));

    // شريط تقدم
    final prog = max(0.0, min(1.0, (0 - game.py) / (0 - game.level.topY)));
    final bgPaint = Paint()..color = const Color(0x40FFFFFF);
    c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(Level.vw - 8, 20, 3, Level.vh - 40),
          const Radius.circular(1.5),
        ),
        bgPaint);
    final fillPaint = Paint()..color = const Color(0xFF9FE870);
    final ph = (Level.vh - 40) * prog;
    c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(Level.vw - 8, Level.vh - 20 - ph, 3, ph),
          const Radius.circular(1.5),
        ),
        fillPaint);

    titlePaint; // silence unused
  }

  void _overlay(Canvas c, String title, String sub) {
    final bg = Paint()..color = const Color(0xB0000000);
    c.drawRect(
        Rect.fromLTWH(0, 0, Level.vw.toDouble(), Level.vh.toDouble()), bg);

    final titleTp = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(c, Offset((Level.vw - titleTp.width) / 2, Level.vh / 2 - 16));

    final subTp = TextPainter(
      text: TextSpan(
        text: sub,
        style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    subTp.paint(c, Offset((Level.vw - subTp.width) / 2, Level.vh / 2 + 6));

    final credit = TextPainter(
      text: const TextSpan(
        text: 'by Ahmed Al-Dheeb',
        style: TextStyle(color: Color(0x88FFFFFF), fontSize: 6),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    credit.paint(c, Offset(Level.vw - credit.width - 6, Level.vh - 8));
  }

  @override
  bool shouldRepaint(covariant GamePainter old) => true;
}