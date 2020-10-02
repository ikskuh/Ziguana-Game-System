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
				fs.Write(BitConverter.GetBytes(bmp.Width), 0, 4);
				fs.Write(BitConverter.GetBytes(bmp.Height), 0, 4);

				var stride = (bmp.Width + 7) / 8;
				
				for(int y = 0; y < bmp.Height; y++)
				{
					var line = new byte[stride];
					for(int x = 0; x < bmp.Width; x++)
					{
						if(bmp.GetPixel(x, y).R == 0xFF)
							line[x / 8] |= (byte)(1<<(x%8));
					}
					fs.Write(line, 0, line.Length);
				}
			}
		}

		return 0;
	}
}
