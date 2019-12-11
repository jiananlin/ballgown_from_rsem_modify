# ballgown_from_rsem_modify
solve an intron position error in ballgownrsem.R from [ballgown](https://github.com/alyssafrazee/ballgown)
ballgown is an downstream RNA-seq Bioconductor package for both gene and isoform level differential analysis. 
In my current project, I need to use the results from RSEM as the input for ballgown, so the function "ballgownrsem" is applied.
I met an error when running this function on the gtf files as below:

Error in .Call2("solve_user_SEW0", start, end, width, PACKAGE = "IRanges") : 
  In range 6: 'end' must be >= 'start' - 1.

This error is resulted from the order of exons in the gtf file. In detail, the exons of genes from the minus strand are listed as the decending order in genomic position and the command below in ballgownrsem [per ballgown](https://github.com/alyssafrazee/ballgown/blob/master/R/ballgownrsem.R) assumes the exons are listed in the ascending order in the genomic position:

introngr = GRanges(seqnames=seqnames(unltrans)[notLast], 
                    ranges=IRanges(start=end(unltrans)[notLast]+1, 
                                   end=start(unltrans)[which(notLast)+1]-1), 
                    strand=strand(unltrans)[notLast])

Therefore, the index of "the next exon" is not simply which(notLast)+1.
I modified the code by reversing the order of exons from the minus strand and the code runs well.

I make this correction public and hope this minor correction can help the users with the same problem.
We should always be grateful that such powerful tools as ballgown were developed.




# Reference
Frazee, Alyssa C., et al. "Ballgown bridges the gap between transcriptome assembly and expression analysis." Nature biotechnology 33.3 (2015): 243.
Li, Bo, and Colin N. Dewey. "RSEM: accurate transcript quantification from RNA-Seq data with or without a reference genome." BMC bioinformatics 12.1 (2011): 323.
