using System;
using System.Drawing;
using System.IO;

class Program
{
  const int tile_size = 8;

  static int Main(string[] args)
  {
    int margin = 1;
    int padding = 1;

    var result = new byte[256 * tile_size];
    using (var bmp = new Bitmap(args[0]))
    {
      if (bmp.Width != 16 * tile_size + 2 * margin + 15 * padding)
        return Error("Invalid image width: {0}", bmp.Width);
      if (bmp.Height != 16 * tile_size + 2 * margin + 15 * padding)
        return Error("Invalid image height: {0}", bmp.Height);

      var chroma_key = bmp.GetPixel(margin, margin);

      for (int c = 0; c < 256; c++)
      {
        int rx = margin + (tile_size + padding) * (c % 16);
        int ry = margin + (tile_size + padding) * (c / 16);

        int offset = tile_size * c;

        for (int y = 0; y < tile_size; y++)
        {
          result[offset + y] = 0x00;
          for (int x = 0; x < tile_size; x++)
          {
            if (bmp.GetPixel(rx + x, ry + y) != chroma_key)
              result[offset + y] += (byte)(1 << x);
          }
        }
      }

      File.WriteAllBytes(args[1], result);
    }
    return 0;
  }

  static int Error(string text)
  {
    Console.Error.WriteLine(text);
    return 1;
  }

  static int Error(string text, params object[] args)
  {
    Console.Error.WriteLine(text, args);
    return 1;
  }
}