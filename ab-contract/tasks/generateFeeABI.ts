import fs from 'fs'
import path from 'path'
import { Fragment } from '@ethersproject/abi'
import { task } from 'hardhat/config'

const basePath = 'src/Facets/'
const libraryBasePath = 'src/Libraries/'

task(
  'feeABI',
  'Generates ABI file for diamond, includes all ABIs of facets'
).setAction(async () => {

  // Create an empty array to store the ABI fragments
  const abi: Fragment[] = []

  // Get a list of all the files in the Facets directory
  let files = ['FeeCollector.sol']

  // Read the compiled ABI of each facet and add it to the abi array
  for (const file of files) {
    const jsonFile = file.replace('sol', 'json')
    const data = fs.readFileSync(
      path.resolve(__dirname, `../out/${file}/${jsonFile}`)
    )
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const json: any = JSON.parse(data.toString())
    abi.push(...json.abi)
  }

  // Remove duplicates from the combined ABI object
  // Filters by checking if the name and type of the
  // function already exists in another ABI fragment
  const cleanAbi = <Fragment[]>abi.filter(
    (item, index, self) =>
      index ===
      self.findIndex((t) => t.name === item.name && t.type === item.type)
  )

  // Write the final ABI to a file
  const finalAbi = JSON.stringify(cleanAbi)
  fs.writeFileSync('./diamondABI/feeCollector.json', finalAbi)
  console.log('ABI written to diamondABI/fee.json')
})
