using System;
using System.IO;
using System.Drawing;

class Program
{
	static int Main(string[] args)
	{
		using(var fs = File.Open(args[1], FileMode.Create, FileAccess.Write))
		{
			using(var bmp = new Bitmap(args[0]))
			{
				for(int i = 0; i < 128; i++)
				{
					var pixels = new byte[8];
					int sx = 6 * (i % 16);
					int sy = 8 * (i / 16);
					for(int y = 0; y < 8; y++)
					{
						byte b = 0;
						for(int x = 0; x < 6; x++)
						{
							if(bmp.GetPixel(sx + x, sy + y).R == 0xFF)
								b |= (byte)(1<<x);
						}
						pixels[y] = b;
					}
					fs.Write(pixels, 0, 8);
				}
			}
		}

		return 0;
	}
}
