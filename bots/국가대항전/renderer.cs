using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

public class Scene {
    public string Kind; public double Start; public double End; public double Mark;
    public Scene(string kind, double start, double end, double mark) { Kind = kind; Start = start; End = end; Mark = mark; }
}

public class Sub {
    public double Start; public double End; public string Text;
    public Sub(double start, double end, string text) { Start = start; End = end; Text = text; }
}

// 서울 외국인 국가대항전 쇼츠 렌더러 (쇼츠3 랭킹 렌더러 기반, 모바일 안전 영역)
public static class Shorts {  // 색 테마: 틸
    public const int W = 1080, H = 1920;
    static readonly Color BG = Color.FromArgb(4, 47, 46);
    static readonly Color WHITE = Color.FromArgb(240, 253, 250);
    static readonly Color MUTED = Color.FromArgb(94, 234, 212);
    static readonly Color DOT = Color.FromArgb(75, 127, 122);
    static readonly Color ORANGE = Color.FromArgb(251, 146, 60);
    static readonly Color CARD = Color.FromArgb(19, 78, 74);

    // 모바일 안전 영역: 내용은 x 60~900, y 220~1460. 자막 y≈1370, 최대 2줄.
    const float SL = 60, SR = 900, SCX = 480, TOP = 230;

    // 데이터 (0 = 1위)
    public static string[] Name;
    public static double[] A, Bv, Ratio;          // A = 비교 기준(평일), Bv = 랭킹 값(주말)
    public static string LabelA = "", LabelB = "", Unit = "명", Series = "", Source = "";
    public static string[] Badge, CardSub;        // 순위별 카드 큰 글씨(예: +3.9%) / 작은 글씨(예: 지난주 2위 → 1위)
    public static string CoverPre = "", CoverBig = "", FlagDir = "";
    static Dictionary<string, Image> flags = new Dictionary<string, Image>();
    static void Flag(Graphics g, string name, float x, float y, float w, double a) {
        if (a <= 0) return;
        Image im;
        if (!flags.TryGetValue(name, out im)) {
            string f = Path.Combine(FlagDir, name + ".png");
            im = File.Exists(f) ? Image.FromFile(f) : null; flags[name] = im;
        }
        if (im == null) return;
        float h = w * im.Height / im.Width;
        using (ImageAttributes ia = new ImageAttributes()) {
            ColorMatrix cm = new ColorMatrix(); cm.Matrix33 = (float)Math.Min(1, a);
            ia.SetColorMatrix(cm);
            g.DrawImage(im, new Rectangle((int)x, (int)y, (int)w, (int)h), 0, 0, im.Width, im.Height, GraphicsUnit.Pixel, ia);
        }
        using (Pen pen = new Pen(Color.FromArgb((int)(60 * Math.Min(1, a)), 255, 255, 255), 2)) g.DrawRectangle(pen, x, y, w, h);
    }
    public static string[] CoverTitle; public static string CoverHi = "", CoverHint = "", OutroBig = "", OutroSmall = "", SummaryTitle = "";

    static Dictionary<string, Font> fonts = new Dictionary<string, Font>();
    static Font F(string style, float size) {
        string key = style + size;
        Font f;
        if (!fonts.TryGetValue(key, out f)) {
            f = new Font(new FontFamily("NanumSquare Neo " + style), size, FontStyle.Regular, GraphicsUnit.Pixel);
            fonts[key] = f;
        }
        return f;
    }
    static SolidBrush B(Color c, double a) { return new SolidBrush(Color.FromArgb((int)(Math.Max(0, Math.Min(1, a)) * c.A), c)); }
    static double C01(double x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
    static double Ease(double x) { x = C01(x); return 1 - Math.Pow(1 - x, 3); }
    static double Back(double x) { x = C01(x); double c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.Pow(x - 1, 3) + c1 * Math.Pow(x - 1, 2); }

    static void Title(Graphics g, string[] lines, string hi, double t, float y0, float size, bool center) {
        StringFormat fmt = (StringFormat)StringFormat.GenericTypographic.Clone();
        fmt.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
        Font font = F("ExtraBold", size);
        float y = y0;
        for (int li = 0; li < lines.Length; li++) {
            double lt = Ease((t - li * 0.12) / 0.45);
            string line = lines[li];
            List<KeyValuePair<string, Color>> parts = new List<KeyValuePair<string, Color>>();
            int i = string.IsNullOrEmpty(hi) ? -1 : line.IndexOf(hi);
            if (i >= 0) {
                parts.Add(new KeyValuePair<string, Color>(line.Substring(0, i), WHITE));
                parts.Add(new KeyValuePair<string, Color>(hi, ORANGE));
                parts.Add(new KeyValuePair<string, Color>(line.Substring(i + hi.Length), WHITE));
            } else parts.Add(new KeyValuePair<string, Color>(line, WHITE));
            float total = g.MeasureString(line, font, 4000, fmt).Width;
            float x = center ? SCX - total / 2 : SL;
            float yy = y + (float)(40 * (1 - lt));
            foreach (KeyValuePair<string, Color> part in parts) {
                if (part.Key.Length == 0) continue;
                using (SolidBrush b = B(part.Value, lt)) g.DrawString(part.Key, font, b, x, yy, fmt);
                x += g.MeasureString(part.Key, font, 4000, fmt).Width;
            }
            y += size * 1.3f;
        }
    }

    static void Card(Graphics g, string big, string small, double t, Color bg, Color fg) {
        if (t <= 0) return;
        double a = Ease(t / 0.35);
        float off = (float)(30 * (1 - a));
        using (SolidBrush b = B(bg, a)) g.FillRectangle(b, SL, 1080 + off, SR - SL, 160);
        using (SolidBrush b = B(fg, a)) g.DrawString(big, F("ExtraBold", 84), b, SL + 28, 1086 + off);
        using (SolidBrush b = B(bg == ORANGE ? BG : WHITE, a)) g.DrawString(small, F("Bold", 38), b, SL + 30, 1186 + off);
    }

    static void SourceLine(Graphics g) {
        using (SolidBrush b = B(MUTED, 1)) g.DrawString(Source, F("Regular", 28), b, SL, 1246);
    }

    static void Subtitle(Graphics g, string text, double frac) {
        Font font = F("Bold", 56);
        StringFormat fmt = new StringFormat(); fmt.Alignment = StringAlignment.Center; fmt.LineAlignment = StringAlignment.Center;
        List<string> lines = new List<string>();
        string cur = "";
        foreach (string w in text.Split(' ')) {
            string tryLine = cur.Length == 0 ? w : cur + " " + w;
            if (cur.Length > 0 && g.MeasureString(tryLine, font).Width > 760) { lines.Add(cur); cur = w; }
            else cur = tryLine;
        }
        if (cur.Length > 0) lines.Add(cur);
        int pages = (lines.Count + 1) / 2, totalLen = 0, acc = 0, page = pages - 1;
        foreach (string l in lines) totalLen += l.Length;
        for (int p = 0; p < pages; p++) {
            int len = lines[2 * p].Length + (2 * p + 1 < lines.Count ? lines[2 * p + 1].Length : 0);
            if (frac * totalLen < acc + len) { page = p; break; }
            acc += len;
        }
        text = lines[2 * page] + (2 * page + 1 < lines.Count ? "\n" + lines[2 * page + 1] : "");
        SizeF sz = g.MeasureString(text, font, 2000, fmt);
        float bw = sz.Width + 60, bh = sz.Height + 32;
        RectangleF box = new RectangleF(SCX - bw / 2, 1370 - bh / 2, bw, bh);
        using (GraphicsPath path = Round(box, 20))
        using (SolidBrush b = new SolidBrush(Color.FromArgb(190, 0, 0, 0))) g.FillPath(b, path);
        using (SolidBrush b = new SolidBrush(Color.White)) g.DrawString(text, font, b, new RectangleF(box.X + 30, box.Y + 16, sz.Width, sz.Height), fmt);
    }
    static GraphicsPath Round(RectangleF r, float d) {
        GraphicsPath p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure(); return p;
    }

    // 값 막대 한 줄: 라벨 + 막대 + 숫자 (숫자는 오른쪽 안전선 넘으면 막대 안쪽으로)
    static void Row(Graphics g, string label, double v, double max, Color c, float y, double t) {
        if (t <= 0) return;
        double a = Ease(t / 0.3), f = Ease((t - 0.15) / 0.9);
        using (SolidBrush b = B(MUTED, a)) g.DrawString(label, F("Bold", 42), b, SL, y);
        using (SolidBrush b = B(CARD, a)) g.FillRectangle(b, SL, y + 62, SR - SL, 110);
        float len = (float)((SR - SL) * v / max * f);
        using (SolidBrush b = B(c, 1)) g.FillRectangle(b, SL, y + 62, len, 110);
        string s = string.Format("{0:N0}{1}", v * f, Unit);
        Font font = F("ExtraBold", 62);
        float tw = g.MeasureString(s, font).Width;
        bool inside = SL + len + 12 + tw > SR;
        float tx = inside ? SL + len - tw - 8 : SL + len + 12;
        using (SolidBrush b = B(inside && c == ORANGE ? BG : WHITE, a)) g.DrawString(s, font, b, tx, y + 82);
    }

    static string R(double r) { return r.ToString("0.0") + "배"; }

    static void DrawScene(Graphics g, Scene s, double t) {
        double lt = t - s.Start, m = s.Mark;
        if (s.Kind == "cover") {
            // 첫 프레임부터 완성된 화면 (썸네일 겸용)
            Title(g, CoverTitle, CoverHi, 5, TOP, 96, false);
            float y = TOP + CoverTitle.Length * 125 + 50;
            using (SolidBrush b = B(WHITE, 1)) g.DrawString(CoverPre, F("ExtraBold", 64), b, SL, y);
            using (SolidBrush b = B(ORANGE, 1)) g.DrawString(CoverBig, F("ExtraBold", CoverBig.Length > 6 ? 150 : 200), b, SL - 10, y + 80);
            Flag(g, Name[0], SL, 968, 150, 1);
            using (SolidBrush b = B(WHITE, 1)) g.DrawString("VS", F("ExtraBold", 56), b, SL + 172, 980);
            Flag(g, Name[1], SL + 270, 968, 150, 1);
            using (SolidBrush b = B(ORANGE, 1)) g.FillRectangle(b, SL, 1110, SR - SL, 170);
            using (SolidBrush b = B(BG, 1)) g.DrawString(CoverHint, F("ExtraBold", 56), b, SL + 30, 1164);
        } else if (s.Kind.StartsWith("r")) {
            int i = int.Parse(s.Kind.Substring(1)) - 1;   // r5 → 인덱스 4
            Color hc = i == 0 ? ORANGE : WHITE;
            double rt = Ease(lt / 0.35);
            float sc = (float)Back(lt / 0.45);
            GraphicsState st = g.Save();
            g.TranslateTransform(SL, TOP + 60); g.ScaleTransform(sc, sc);
            using (SolidBrush b = B(ORANGE, rt)) g.DrawString((i + 1) + "위", F("ExtraBold", 120), b, -10, -60);
            g.Restore(st);
            double fa = Ease((lt - 0.1) / 0.4); float fw = (float)(230 * Back((lt - 0.1) / 0.5));
            if (fw > 1) Flag(g, Name[i], SR - 115 - fw / 2, TOP + 40 + (230 - fw) / 3, fw, fa);
            Title(g, new string[] { Name[i] }, null, lt - 0.15, TOP + 150, Name[i].Length > 9 ? 66 : 80, false);
            double max = Math.Max(A[i], Bv[i]);
            Row(g, LabelA, A[i], max, DOT, 560, lt - 0.4);
            Row(g, LabelB, Bv[i], max, ORANGE, 800, lt - 0.9);
            Card(g, Badge[i], CardSub[i], lt - Math.Max(m, 1.6), i == 0 ? ORANGE : CARD, i == 0 ? BG : ORANGE);
        } else if (s.Kind == "summary") {
            Title(g, new string[] { SummaryTitle }, "TOP5", lt, TOP, 80, false);
            double maxR = Bv[0];
            for (int k = 0; k < Name.Length; k++) {
                double rt = lt - 0.2 - k * 0.12;
                if (rt <= 0) continue;
                double a = Ease(rt / 0.3), f = Ease((rt - 0.1) / 0.7);
                float y = 400 + k * 130;
                Color c = k == 0 ? ORANGE : DOT;
                using (SolidBrush b = B(k == 0 ? ORANGE : WHITE, a)) g.DrawString((k + 1).ToString(), F("ExtraBold", 64), b, SL, y);
                Flag(g, Name[k], SL + 80, y + 6, 66, a);
                using (SolidBrush b = B(WHITE, a)) g.DrawString(Name[k], F("Bold", 44), b, SL + 160, y);
                float len = (float)(420 * Bv[k] / maxR * f);
                using (SolidBrush b = B(c, 1)) g.FillRectangle(b, SL + 80, y + 64, len, 30);
                using (SolidBrush b = B(k == 0 ? ORANGE : MUTED, a)) g.DrawString(string.Format("{0:N0}명", Bv[k]), F("ExtraBold", 40), b, SL + 96 + len, y + 56);
            }
            Card(g, OutroBig, OutroSmall, lt - m, CARD, ORANGE);
        }
        if (s.Start > 0 && lt < 0.25) using (SolidBrush b = B(BG, 1 - Ease(lt / 0.25))) g.FillRectangle(b, 0, 0, W, H);
    }

    public static int Render(string dir, int fps, Scene[] scenes, Sub[] subs, double total) {
        int n = (int)Math.Ceiling(total * fps);
        using (Bitmap bmp = new Bitmap(W, H, PixelFormat.Format24bppRgb))
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;
            for (int fi = 0; fi < n; fi++) {
                double t = (double)fi / fps;
                g.Clear(BG);
                bool cover = false;
                for (int si = 0; si < scenes.Length; si++) {
                    Scene s = scenes[si];
                    if (t >= s.Start && t < s.End) { DrawScene(g, s, t); cover = s.Kind == "cover"; if (si == scenes.Length - 1) SourceLine(g); break; }
                }
                if (!cover) foreach (Sub su in subs) if (t >= su.Start && t < su.End) { Subtitle(g, su.Text, (t - su.Start) / (su.End - su.Start)); break; }
                bmp.Save(Path.Combine(dir, string.Format("f_{0:D5}.png", fi)), ImageFormat.Png);
            }
        }
        return n;
    }
}
