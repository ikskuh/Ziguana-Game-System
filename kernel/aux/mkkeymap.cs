using System;
using System.IO;
using System.Text;

class Program
{
	static byte KeyToByte(string val)
	{
		if(val.Length > 1 && val[0] == '\\') {
			return Convert.ToByte(val.Substring(1), 16);
		}
		var x = Encoding.ASCII.GetBytes(val);
		if(x.Length != 1)
			throw new InvalidOperationException(val);
		return x[0];
	}
	static int Main(string[] args)
	{
		var keymap = new byte[4 * 128];
		using(var sr = new StreamReader(args[0], Encoding.UTF8))
		{
			while(!sr.EndOfStream)
			{
				var line = sr.ReadLine();
				if(line.StartsWith("#"))
					continue;
				if(line.Length == 0)
					continue;
				var parts = line.Split('\t');
				if(parts.Length < 2 || parts.Length > 5)
					throw new InvalidOperationException("Kaputt: " + line);
				if(parts.Length > 2)
				{
					var index = int.Parse(parts[0]);
					var lower = parts[2];
					var upper = (parts.Length >= 4) ? parts[3] : lower;
					var graph = (parts.Length >= 5) ? parts[4] : lower;
					
					keymap[4 * index + 1] = KeyToByte(lower);
					keymap[4 * index + 2] = KeyToByte(upper);
					keymap[4 * index + 3] = KeyToByte(graph);
				}
			}
		}
		using(var fs = File.Open(args[1], FileMode.Create, FileAccess.Write))
		{
			fs.Write(keymap, 0, keymap.Length);
		}
		return 0;
	}
}
