using System;
using System.Drawing;
using System.IO;

class Program
{
  static int Main(string[] args)
  {
    var result = new byte[256 * 6];
    using (var bmp = new Bitmap(args[0]))
    {
      if (bmp.Width != 96)
        return Error("Invalid image width: {0}", bmp.Width);
      if (bmp.Height != 96)
        return Error("Invalid image height: {0}", bmp.Height);

      var chroma_key = bmp.GetPixel(0, 0);

      for (int c = 0; c < 256; c++)
      {
        int rx = 6 * (c % 16);
        int ry = 6 * (c / 16);

        int offset = 6 * c;

        for (int y = 0; y < 6; y++)
        {
          result[offset + y] = 0x00;
          for (int x = 0; x < 6; x++)
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